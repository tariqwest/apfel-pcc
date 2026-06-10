// ============================================================================
// ModelBackendTests.swift - Tests for the on-device vs PCC backend selector.
// ============================================================================

import Foundation
import ApfelCore

func runModelBackendTests() {
    test("defaults to onDevice") {
        try assertEqual(ModelBackend.default, .onDevice)
    }

    test("on-device canonical model id") {
        try assertEqual(ModelBackend.onDevice.canonicalModelID, "apple-foundationmodel")
    }

    test("PCC canonical model id") {
        try assertEqual(ModelBackend.privateCloudCompute.canonicalModelID, "apple-foundationmodel-pcc")
    }

    test("parse nil model -> onDevice") {
        try assertEqual(ModelBackend.from(modelName: nil), .onDevice)
    }

    test("parse empty model -> onDevice") {
        try assertEqual(ModelBackend.from(modelName: ""), .onDevice)
    }

    test("parse default model -> onDevice") {
        try assertEqual(ModelBackend.from(modelName: "default"), .onDevice)
    }

    test("parse apfel-plus -> onDevice") {
        try assertEqual(ModelBackend.from(modelName: "apfel-plus"), .onDevice)
    }

    test("parse canonical on-device id -> onDevice") {
        try assertEqual(ModelBackend.from(modelName: "apple-foundationmodel"), .onDevice)
    }

    test("parse arbitrary value -> onDevice (forward-compat)") {
        // Unknown ids fall back to on-device. OpenAI clients often pass
        // hard-coded ids like "gpt-4" - we keep serving them locally rather
        // than 400ing.
        try assertEqual(ModelBackend.from(modelName: "gpt-4"), .onDevice)
    }

    test("parse pcc alias -> privateCloudCompute") {
        try assertEqual(ModelBackend.from(modelName: "pcc"), .privateCloudCompute)
    }

    test("parse apfel-plus-pcc alias -> privateCloudCompute") {
        try assertEqual(ModelBackend.from(modelName: "apfel-plus-pcc"), .privateCloudCompute)
    }

    test("parse canonical pcc id -> privateCloudCompute") {
        try assertEqual(ModelBackend.from(modelName: "apple-foundationmodel-pcc"), .privateCloudCompute)
    }

    test("parse is case-insensitive") {
        try assertEqual(ModelBackend.from(modelName: "PCC"), .privateCloudCompute)
        try assertEqual(ModelBackend.from(modelName: "Apple-FoundationModel-PCC"), .privateCloudCompute)
    }

    test("parse trims whitespace") {
        try assertEqual(ModelBackend.from(modelName: "  pcc  "), .privateCloudCompute)
    }

    test("display label is on-device") {
        try assertEqual(ModelBackend.onDevice.displayLabel, "on-device")
    }

    test("display label is Private Cloud Compute") {
        try assertEqual(ModelBackend.privateCloudCompute.displayLabel, "Private Cloud Compute")
    }
}
