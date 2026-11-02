"""Cross-check the merged native service, manifest and relocated app assets."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'apps/mobile'


class MobileIntegrationTest(unittest.TestCase):
    def test_native_components_and_permissions_coexist(self):
        manifest = ET.parse(APP / 'android/app/src/main/AndroidManifest.xml').getroot()
        name = '{http://schemas.android.com/apk/res/android}name'
        application = manifest.find('application')
        self.assertIn('.RecognitionService', [node.get(name) for node in application.findall('service')])
        self.assertIn('.DatedAlarmReceiver', [node.get(name) for node in application.findall('receiver')])
        permissions = {node.get(name) for node in manifest.findall('uses-permission')}
        for permission in ['CAMERA', 'INTERNET', 'FOREGROUND_SERVICE', 'SCHEDULE_EXACT_ALARM', 'POST_NOTIFICATIONS']:
            self.assertIn('android.permission.' + permission, permissions)

    def test_background_capture_cannot_bypass_review(self):
        native = APP / 'android/app/src/main'
        service = (native / 'java/com/example/testsign/RecognitionService.java').read_text(encoding='utf-8')
        activity = (native / 'kotlin/com/example/testsign/MainActivity.kt').read_text(encoding='utf-8')
        self.assertNotIn('adjustStreamVolume', service)
        self.assertNotIn('executePipCommand', service)
        self.assertNotIn('executeNativeCommand', activity)
        self.assertIn('running.collect(command, display)', service)
        self.assertIn('"takeInput" ->', activity)

    def test_new_assets_and_pipeline_use_mobile_paths(self):
        self.assertTrue((APP / 'assets/branding/signbridge_sb.png').is_file())
        self.assertTrue((APP / 'assets/branding/signbridge_logo.png').is_file())
        for name in ['CameraPipeline.java', 'RecognitionService.java', 'BackgroundCommandGate.java']:
            self.assertTrue((APP / 'android/app/src/main/java/com/example/testsign' / name).is_file())
        self.assertFalse((ROOT / 'android/app/src/main/kotlin/com/example/testsign/MainActivity.kt').exists())


if __name__ == '__main__':
    unittest.main()
