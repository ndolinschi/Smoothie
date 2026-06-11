plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    iosArm64 {
        binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }
    iosSimulatorArm64 {
        binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }
    macosArm64 {
        binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }

    applyDefaultHierarchyTemplate()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines)
            implementation(libs.kotlinx.serialization.json)
            // Ktor client only — handoff context compressor talks to Gemini Flash.
            // HTTP server lives in Swift (Hummingbird) on the Mac since Ktor 3.x
            // does not yet ship a Native server target.
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.content.negotiation)
            implementation(libs.ktor.serialization.json)
        }

        appleMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
