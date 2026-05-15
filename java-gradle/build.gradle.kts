plugins {
    java
    id("org.cyclonedx.bom") version "1.8.2"
    id("org.owasp.dependencycheck") version "9.2.0"
}

group = "com.example"
version = "1.0.0"

repositories {
    // Use a private proxy for all artifact resolution.
    // This gates downloads through a scanned, controlled repository.
    // Uncomment and replace with your Nexus/Artifactory URL.
    // maven {
    //     url = uri("https://nexus.internal.company.com/repository/maven-public/")
    //     credentials {
    //         username = providers.environmentVariable("NEXUS_USERNAME").get()
    //         password = providers.environmentVariable("NEXUS_PASSWORD").get()
    //     }
    // }
    mavenCentral()
}

// Dependency locking: pins all resolved versions to lock files.
// Location: gradle/dependency-locks/*.lock
// Generate: ./gradlew dependencies --write-locks
// Update single dep: ./gradlew dependencies --update-locks org.example:lib
// Verify: ./gradlew build (reads lock files automatically)
dependencyLocking {
    lockAllConfigurations()
    // Lock file location (default: gradle/dependency-locks/)
    lockMode.set(LockMode.STRICT)  // Fail if lock file is missing or outdated
}

dependencies {
    // Pin exact versions (no dynamic versions like 1.+ or latest.release)
    // implementation("com.google.guava:guava:33.2.1-jre")
}

// OWASP Dependency-Check configuration
dependencyCheck {
    // Fail build on CVSS score >= 7.0
    failBuildOnCVSS = 7f
    // Output formats
    format = org.owasp.dependencycheck.reporting.ReportGenerator.Format.ALL.toString()
    // Suppress false positives (document each suppression)
    // suppressionFile = "dependency-check-suppression.xml"
}

// CycloneDX SBOM
cyclonedxBom {
    includeConfigs.set(listOf("runtimeClasspath"))
    schemaVersion.set("1.5")
    destination.set(project.file("${buildDir}/reports"))
    outputFormat.set("json")
    outputName.set("bom")
}

tasks.register("securityCheck") {
    group = "verification"
    description = "Run full supply chain security checks"
    dependsOn("dependencyCheckAnalyze", "cyclonedxBom")
}
