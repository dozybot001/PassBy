import com.android.build.api.artifact.SingleArtifact

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

android {
    namespace = "cn.tenonai.apps.passby"
    compileSdk = 37
    buildToolsVersion = "37.0.0"

    defaultConfig {
        applicationId = "cn.tenonai.apps.passby"
        minSdk = 26
        targetSdk = 37
        versionCode = 5
        versionName = "2.2.0"
    }

    androidResources {
        // The app is written in English and Simplified Chinese; other translations in libraries are dropped.
        localeFilters += listOf("en", "zh")
    }

    buildTypes {
        debug {
            // Lets a debug build sit beside the released app. It is signed with the debug key.
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.all {
            // The shared vectors are read where they are, not copied into android/.
            it.systemProperty("passby.vectors", rootProject.file("../docs/export-vectors.json").path)
            it.systemProperty("passby.syncVectors", rootProject.file("../docs/sync-vectors.json").path)
            // One test reads the app's own sources, to check which files can open a network connection.
            it.systemProperty("passby.sources", file("src/main/kotlin").path)
            it.inputs.dir(file("src/main/kotlin"))
        }
    }
}

// Every resolved version is written to app/gradle.lockfile. A build fails if a version drifts from it;
// `./gradlew :app:dependencies --write-locks` updates it on purpose.
dependencyLocking {
    lockAllConfigurations()
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.activity.compose)
    implementation(libs.biometric)
    implementation(libs.fragment)

    testImplementation(libs.junit)
    testImplementation(libs.zxing.core)
}

/**
 * The app asks for as little as it can. This fails the build if the manifest that goes into the
 * package, after every library's manifest is merged in, asks for a permission outside the short list
 * below.
 */
abstract class CheckPermissions : DefaultTask() {
    @get:InputFile
    abstract val mergedManifest: RegularFileProperty

    @get:Input
    abstract val allowed: SetProperty<String>

    @TaskAction
    fun check() {
        val text = mergedManifest.get().asFile.readText()
        val requested = Regex("""<uses-permission(?:-sdk-\d+)?\s[^>]*android:name="([^"]+)"""").findAll(text).map { it.groupValues[1] }.toSet()
        val unexpected = requested - allowed.get()
        if (unexpected.isNotEmpty()) {
            throw GradleException("The merged manifest requests permissions the app must not have: $unexpected")
        }
        logger.lifecycle("Permissions in the merged manifest: ${requested.sorted()}")
    }
}

androidComponents {
    onVariants { variant ->
        val name = variant.name.replaceFirstChar { it.uppercase() }
        val check = tasks.register<CheckPermissions>("check${name}Permissions") {
            mergedManifest.set(variant.artifacts.get(SingleArtifact.MERGED_MANIFEST))
            // Both come from androidx.biometric and only allow asking the system to verify the person.
            allowed.addAll("android.permission.USE_BIOMETRIC", "android.permission.USE_FINGERPRINT")
            // For AI grouping, which is off until the person turns it on, and for sync on the local
            // network. Two files open connections (system/AiClient.kt, core/SyncTransport.kt); a unit
            // test checks that no other can.
            allowed.add("android.permission.INTERNET")
            // For sync between two devices on the same local network (core/SyncTransport.kt). Android 17
            // and later ask the person for it; it is requested on the sync page only.
            allowed.add("android.permission.ACCESS_LOCAL_NETWORK")
            // Declared by androidx.core for receivers the app registers for itself; it is the app's own
            // signature-level permission and grants nothing outside the app.
            allowed.add(variant.applicationId.map { "$it.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" })
        }
        tasks.matching { it.name == "assemble$name" || it.name == "package$name" }.configureEach { dependsOn(check) }
    }
}
