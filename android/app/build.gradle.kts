import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciais de assinatura ficam FORA do repositório, em android/key.properties
// (já coberto por android/.gitignore). O arquivo é opcional de propósito: sem
// ele, o build de debug e o CI continuam funcionando numa máquina limpa — só o
// release deixa de ser publicável, e diz isso em voz alta.
val arquivoKeystore = rootProject.file("key.properties")
val propriedadesKeystore = Properties().apply {
    if (arquivoKeystore.exists()) {
        FileInputStream(arquivoKeystore).use { load(it) }
    }
}
val temKeystoreDeRelease = arquivoKeystore.exists()

// O aviso mora aqui, no escopo do script, e não dentro de `buildTypes`: ali o
// receptor é `ApplicationBuildType` e `logger` não resolve de forma garantida.
// Só dispara quando alguém pediu release de fato — avisar em todo build de
// debug vira ruído que se aprende a ignorar.
val pedindoRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (pedindoRelease && !temKeystoreDeRelease) {
    logger.warn(
        "AVISO: android/key.properties não encontrado. O build de release será " +
            "assinado com a CHAVE DE DEBUG e a Play Store vai recusá-lo. " +
            "Veja android/key.properties.exemplo.",
    )
}

android {
    namespace = "dev.lucas.app_estudos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Exigido pelo flutter_local_notifications (java.time em minSdk < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.lucas.app_estudos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (temKeystoreDeRelease) {
            create("release") {
                keyAlias = propriedadesKeystore.getProperty("keyAlias")
                keyPassword = propriedadesKeystore.getProperty("keyPassword")
                storeFile = propriedadesKeystore.getProperty("storeFile")
                    ?.let { rootProject.file(it) }
                storePassword = propriedadesKeystore.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Antes: `signingConfigs.getByName("debug")` fixo — o AAB de release
            // saía assinado com a chave de debug, que a Play Store recusa e
            // qualquer um consegue reproduzir. O fallback continua existindo
            // para `flutter run --release` funcionar em máquina sem keystore,
            // mas agora avisa em vez de fingir que está tudo certo.
            signingConfig = if (temKeystoreDeRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
