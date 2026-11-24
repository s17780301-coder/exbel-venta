"""Ajusta el proyecto Android que genera `flutter create` para exBel Alerta."""
import base64, os, re, pathlib

raiz = pathlib.Path('android/app')
man = raiz / 'src/main/AndroidManifest.xml'
s = man.read_text()

permisos = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
'''
s = re.sub(r'(<manifest[^>]*>)', r'\1' + permisos, s, count=1)
s = re.sub(r'android:label="[^"]*"', 'android:label="exBel Alerta"', s, count=1)

extra = '''
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="specialUse"
            android:exported="false">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Recibe alertas de emergencia de las cajas de la tienda"/>
        </service>
        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
            android:authorities="${applicationId}.ota_update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/filepaths"/>
        </provider>
'''
s = s.replace('</application>', extra + '    </application>', 1)
man.write_text(s)

xml = raiz / 'src/main/res/xml'
xml.mkdir(parents=True, exist_ok=True)
(xml / 'filepaths.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
<files-path name="internal_apk_storage" path="ota_update/"/>
</paths>
''')

# Gradle: SDK mínimo, multidex y firma fija (para que las actualizaciones instalen encima).
kts = raiz / 'build.gradle.kts'
g = kts.read_text()
g = re.sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 23', g, count=1)
g = re.sub(r'(defaultConfig\s*\{)', r'\1\n        multiDexEnabled = true', g, count=1)
# Firma fija desde los secretos de GitHub (ALERTA_FIRMA en base64 y ALERTA_CLAVE).
# Sin secretos se usa la firma de prueba: instala, pero no se actualiza encima.
b64 = os.environ.get('ALERTA_FIRMA', '').strip()
clave = os.environ.get('ALERTA_CLAVE', '').strip()
if b64 and clave:
    pathlib.Path('ci/firma.jks').write_bytes(base64.b64decode(b64))
    firma = """
    signingConfigs {
        create("exbel") {
            storeFile = file("../../ci/firma.jks")
            storePassword = System.getenv("ALERTA_CLAVE")
            keyAlias = "exbel"
            keyPassword = System.getenv("ALERTA_CLAVE")
        }
    }
"""
    g = re.sub(r'(\n\s*buildTypes\s*\{)', firma + r'\1', g, count=1)
    g = g.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("exbel")')
    print('Firma: exBel')
else:
    print('Firma: de prueba (faltan los secretos ALERTA_FIRMA y ALERTA_CLAVE)')
kts.write_text(g)
