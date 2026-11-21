@testable import App
import Foundation
import Testing

struct SupplementUPCTests {
    @Test func scannerEAN13WithLeadingZeroBecomesUPCA() throws {
        let n = try SupplementUPC.normalize("0748927028669")
        #expect(n.canonical == "748927028669")
        #expect(n.upcA == "748927028669")
        #expect(n.ean13 == "0748927028669")
    }

    @Test func upcAPadsToEAN13AndGroupsForDSLD() throws {
        let n = try SupplementUPC.normalize("7 48927 02866 9")
        #expect(n.canonical == "748927028669")
        #expect(n.dsldPhrases.first == "\"7 48927 02866 9\"")
        #expect(n.matchDigits.contains("0748927028669"))
    }

    @Test func droppedLeadingZeroIsRestored() throws {
        // Nature Made 0 31604 02616 5 typed without the leading zero.
        let n = try SupplementUPC.normalize("31604026165")
        #expect(n.canonical == "031604026165")
    }

    @Test func gtin14WithZeroIndicatorIsTheSameProduct() throws {
        #expect(try SupplementUPC.normalize("00748927028669").canonical == "748927028669")
    }

    @Test func realEAN13StaysEAN13() throws {
        let n = try SupplementUPC.normalize("4006381333931")
        #expect(n.canonical == "4006381333931")
        #expect(n.upcA == nil)
    }

    @Test func upcEExpandsToUPCA() throws {
        // UPC-E 01234565 → UPC-A 012345000065.
        #expect(try SupplementUPC.normalize("01234565").canonical == "012345000065")
    }

    @Test func badCheckDigitAndBadLengthThrow() {
        #expect(throws: SupplementUPC.Failure.badCheckDigit) { try SupplementUPC.normalize("748927028660") }
        #expect(throws: SupplementUPC.Failure.badLength) { try SupplementUPC.normalize("12345") }
    }

    @Test func realSupplementBarcodesPassTheCheckDigit() {
        for code in ["748927028669", "031604026165", "768990017926", "748927060140"] {
            #expect(SupplementUPC.isValidGTIN(code), "\(code)")
        }
    }
}
