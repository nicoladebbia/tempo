import Fluent
import Foundation
import Vapor

// MARK: - Brand Catalog Item Fluent Model

// One product row in the optional brand/size catalog (see
// CreateBrandCatalogItems for sourcing/scope notes).

final class BrandCatalogItem: Model, Content, @unchecked Sendable {
    static let schema = "brand_catalog_items"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "brand")
    var brand: String

    @OptionalField(key: "chain")
    var chain: String?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "generic_name")
    var genericName: String?

    @OptionalField(key: "size_value")
    var sizeValue: Double?

    @OptionalField(key: "size_unit")
    var sizeUnit: String?

    @OptionalField(key: "pack_count")
    var packCount: Int?

    @OptionalField(key: "barcode")
    var barcode: String?

    @OptionalField(key: "image_url")
    var imageURL: String?

    @OptionalField(key: "categories")
    var categories: [String]?

    @Field(key: "updated_at")
    var updatedAt: Date

    @Field(key: "is_stale")
    var isStale: Bool

    init() {}

    init(
        id: UUID? = nil,
        brand: String,
        chain: String? = nil,
        name: String,
        genericName: String? = nil,
        sizeValue: Double? = nil,
        sizeUnit: String? = nil,
        packCount: Int? = nil,
        barcode: String? = nil,
        imageURL: String? = nil,
        categories: [String]? = nil,
        isStale: Bool = false
    ) {
        self.id = id
        self.brand = brand
        self.chain = chain
        self.name = name
        self.genericName = genericName
        self.sizeValue = sizeValue
        self.sizeUnit = sizeUnit
        self.packCount = packCount
        self.barcode = barcode
        self.imageURL = imageURL
        self.categories = categories
        updatedAt = Date()
        self.isStale = isStale
    }
}
