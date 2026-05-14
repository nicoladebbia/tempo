import Fluent
import Vapor

// MARK: - ReceiptController

// Routes:
//   POST   /v1/nutrition/receipts/structure   — call Haiku Vision, return structured items (no DB write)
//   POST   /v1/nutrition/receipts             — persist a receipt + its line items
//   GET    /v1/nutrition/receipts             — list current user's receipts
//   GET    /v1/nutrition/receipts/:id         — fetch one receipt with line items
//   PATCH  /v1/nutrition/receipts/:id/line-items/:lineID — update a line (canonical, qty, confirmed)
//   DELETE /v1/nutrition/receipts/:id         — cascade-delete a receipt

struct ReceiptController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // /structure invokes Claude Haiku Vision and is Pro-only.
        // Per MONETIZATION_STRATEGY.md §3 + INTELLIGENCE_REMEDIATION_PLAN.md §4.
        routes.grouped(SubscriptionMiddleware()).post("structure", use: structure)
        routes.post(use: create)
        routes.get(use: list)
        routes.group(":receiptID") { receipt in
            receipt.get(use: fetch)
            receipt.delete(use: delete)
            receipt.group("line-items", ":lineID") { line in
                line.patch(use: updateLine)
            }
        }
    }

    // MARK: - POST /structure

    @Sendable
    func structure(req: Request) async throws -> Envelope<ReceiptStructuringResponseDTO> {
        _ = try req.auth.requireUserID()
        let dto = try req.content.decode(ReceiptStructuringRequestDTO.self)
        let response = try await ReceiptStructuringService.shared.structureReceipt(request: dto, on: req)
        return Envelope(data: response, requestID: req.requestID)
    }

    // MARK: - POST /

    @Sendable
    func create(req: Request) async throws -> Envelope<ReceiptDTO> {
        let userID = try req.auth.requireUserID()
        let input = try req.content.decode(CreateReceiptInput.self)
        let receipt = Receipt(
            userID: userID,
            store: input.store,
            purchaseDate: input.purchaseDate ?? Date(),
            totalAmount: input.totalAmount ?? 0,
            ocrStatus: input.ocrStatus ?? "awaiting_review",
            ocrProvider: input.ocrProvider ?? "vision_and_haiku"
        )
        receipt.storeLocation = input.storeLocation
        receipt.taxAmount = input.taxAmount
        receipt.paymentMethod = input.paymentMethod
        receipt.photoPath = input.photoPath
        receipt.ocrRawText = input.ocrRawText

        try await receipt.save(on: req.db)

        for item in input.lineItems {
            let line = ReceiptLineItem(
                receiptID: receipt.id ?? "",
                rawText: item.rawText,
                canonicalFoodName: item.canonicalFoodName,
                displayName: item.displayName,
                quantity: item.quantity,
                unit: item.unit,
                totalPrice: item.totalPrice,
                confidence: item.confidence
            )
            line.quantityGrams = item.quantityGrams
            line.unitPrice = item.unitPrice
            line.pricePerKg = item.pricePerKg
            line.onSale = item.onSale
            line.saleNote = item.saleNote
            try await line.save(on: req.db)
        }

        try await receipt.$lineItems.load(on: req.db)
        return Envelope(data: ReceiptDTO(model: receipt), requestID: req.requestID)
    }

    // MARK: - GET /

    @Sendable
    func list(req: Request) async throws -> Envelope<[ReceiptDTO]> {
        let userID = try req.auth.requireUserID()
        let receipts = try await Receipt.query(on: req.db)
            .filter(\.$userID == userID)
            .with(\.$lineItems)
            .sort(\.$createdAt, .descending)
            .limit(100)
            .all()
        return Envelope(data: receipts.map(ReceiptDTO.init(model:)), requestID: req.requestID)
    }

    // MARK: - GET /:receiptID

    @Sendable
    func fetch(req: Request) async throws -> Envelope<ReceiptDTO> {
        let userID = try req.auth.requireUserID()
        guard let id = req.parameters.get("receiptID") else {
            throw Abort(.badRequest, reason: "Missing receiptID.")
        }
        guard let receipt = try await Receipt.query(on: req.db)
            .filter(\.$id == id)
            .filter(\.$userID == userID)
            .with(\.$lineItems)
            .first()
        else {
            throw Abort(.notFound, reason: "Receipt not found.")
        }
        return Envelope(data: ReceiptDTO(model: receipt), requestID: req.requestID)
    }

    // MARK: - PATCH /:receiptID/line-items/:lineID

    @Sendable
    func updateLine(req: Request) async throws -> Envelope<ReceiptLineItemDTO> {
        let userID = try req.auth.requireUserID()
        guard let receiptID = req.parameters.get("receiptID"),
              let lineID = req.parameters.get("lineID")
        else {
            throw Abort(.badRequest, reason: "Missing receiptID or lineID.")
        }
        // Ensure user owns the parent receipt.
        guard let receipt = try await Receipt.query(on: req.db)
            .filter(\.$id == receiptID)
            .filter(\.$userID == userID)
            .first()
        else {
            throw Abort(.notFound, reason: "Receipt not found.")
        }
        guard let line = try await ReceiptLineItem.query(on: req.db)
            .filter(\.$id == lineID)
            .filter(\.$receipt.$id == receiptID)
            .first()
        else {
            throw Abort(.notFound, reason: "Line item not found.")
        }

        let patch = try req.content.decode(UpdateReceiptLineInput.self)
        if let v = patch.canonicalFoodName { line.canonicalFoodName = v }
        if let v = patch.displayName { line.displayName = v }
        if let v = patch.quantity { line.quantity = v }
        if let v = patch.unit { line.unit = v }
        if let v = patch.totalPrice { line.totalPrice = v }
        if let v = patch.userConfirmed { line.userConfirmed = v }
        if let v = patch.linkedPantryItemID { line.linkedPantryItemID = v }
        try await line.save(on: req.db)

        receipt.updatedAt = Date()
        try await receipt.save(on: req.db)

        return Envelope(data: ReceiptLineItemDTO(model: line), requestID: req.requestID)
    }

    // MARK: - DELETE /:receiptID

    @Sendable
    func delete(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let id = req.parameters.get("receiptID") else {
            throw Abort(.badRequest, reason: "Missing receiptID.")
        }
        guard let receipt = try await Receipt.query(on: req.db)
            .filter(\.$id == id)
            .filter(\.$userID == userID)
            .first()
        else {
            throw Abort(.notFound, reason: "Receipt not found.")
        }
        // Cascade is enforced at schema level; just delete the parent.
        try await receipt.delete(on: req.db)
        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }
}

// MARK: - Input DTOs

struct CreateReceiptInput: Content {
    let store: String
    let storeLocation: String?
    let purchaseDate: Date?
    let totalAmount: Double?
    let taxAmount: Double?
    let paymentMethod: String?
    let photoPath: String?
    let ocrStatus: String?
    let ocrRawText: String?
    let ocrProvider: String?
    let lineItems: [CreateReceiptLineInput]
}

struct CreateReceiptLineInput: Content {
    let rawText: String
    let canonicalFoodName: String
    let displayName: String
    let quantity: Double
    let unit: String
    let quantityGrams: Double?
    let unitPrice: Double?
    let totalPrice: Double
    let pricePerKg: Double?
    let onSale: Bool
    let saleNote: String?
    let confidence: Double
}

struct UpdateReceiptLineInput: Content {
    let canonicalFoodName: String?
    let displayName: String?
    let quantity: Double?
    let unit: String?
    let totalPrice: Double?
    let userConfirmed: Bool?
    let linkedPantryItemID: String?
}

// MARK: - Output DTOs

struct ReceiptDTO: Content {
    let id: String
    let store: String
    let storeLocation: String?
    let purchaseDate: Date
    let totalAmount: Double
    let taxAmount: Double?
    let paymentMethod: String?
    let photoPath: String?
    let ocrStatus: String
    let ocrRawText: String?
    let ocrProvider: String
    let userReviewed: Bool
    let createdAt: Date
    let updatedAt: Date
    let lineItems: [ReceiptLineItemDTO]

    init(model: Receipt) {
        id = model.id ?? ""
        store = model.store
        storeLocation = model.storeLocation
        purchaseDate = model.purchaseDate
        totalAmount = model.totalAmount
        taxAmount = model.taxAmount
        paymentMethod = model.paymentMethod
        photoPath = model.photoPath
        ocrStatus = model.ocrStatus
        ocrRawText = model.ocrRawText
        ocrProvider = model.ocrProvider
        userReviewed = model.userReviewed
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        lineItems = ((try? model.$lineItems.value) ?? [])?.map(ReceiptLineItemDTO.init(model:)) ?? []
    }
}

struct ReceiptLineItemDTO: Content {
    let id: String
    let rawText: String
    let canonicalFoodName: String
    let displayName: String
    let quantity: Double
    let unit: String
    let quantityGrams: Double?
    let unitPrice: Double?
    let totalPrice: Double
    let pricePerKg: Double?
    let onSale: Bool
    let saleNote: String?
    let confidence: Double
    let userConfirmed: Bool
    let linkedPantryItemID: String?
    let createdAt: Date

    init(model: ReceiptLineItem) {
        id = model.id ?? ""
        rawText = model.rawText
        canonicalFoodName = model.canonicalFoodName
        displayName = model.displayName
        quantity = model.quantity
        unit = model.unit
        quantityGrams = model.quantityGrams
        unitPrice = model.unitPrice
        totalPrice = model.totalPrice
        pricePerKg = model.pricePerKg
        onSale = model.onSale
        saleNote = model.saleNote
        confidence = model.confidence
        userConfirmed = model.userConfirmed
        linkedPantryItemID = model.linkedPantryItemID
        createdAt = model.createdAt
    }
}
