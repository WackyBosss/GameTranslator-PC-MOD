import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 250), 
    center: true,
    backgroundColor: Colors.transparent, 
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, 
    alwaysOnTop: true, 
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const RemotePlayTranslatorApp());
}

class RemotePlayTranslatorApp extends StatelessWidget {
  const RemotePlayTranslatorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const OverlayTranslationScreen(),
    );
  }
}

class OverlayTranslationScreen extends StatefulWidget {
  const OverlayTranslationScreen({Key? key}) : super(key: key);

  @override
  State<OverlayTranslationScreen> createState() => _OverlayTranslationScreenState();
}

class _OverlayTranslationScreenState extends State<OverlayTranslationScreen> {
  final String _deepLApiKey = "SENIN_DEEPL_API_ANAHTARIN"; 
  final String _ocrApiKey = "K88888888888888"; 

  String _translatedText = "Uygulamayı PS Remote Play altyazılarının üzerine sürükleyin...";
  String _originalText = "Hazır.";
  String _detectedLang = "";
  
  Timer? _captureTimer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startScreenCaptureLoop();
  }

  void _startScreenCaptureLoop() {
    _captureTimer = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        Rect bounds = await windowManager.getBounds();
        
        CapturedData? capturedData = await screenCapturer.capture(
          mode: CaptureMode.region,
          copyToClipboard: false,
          region: bounds, 
        );

        if (capturedData != null && capturedData.imageBytes != null) {
          String extractedText = await _performCloudOCR(capturedData.imageBytes!);
          
          if (extractedText.isNotEmpty && extractedText != _originalText) {
            await _translateWithDeepL(extractedText);
          }
        }
      } catch (e) {
        debugPrint("Ekran Yakalama Hatası: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<String> _performCloudOCR(List<int> imageBytes) async {
    final url = Uri.parse('https://api.ocr.space/parse/image');
    
    var request = http.MultipartRequest('POST', url)
      ..fields['apikey'] = _ocrApiKey
      ..fields['language'] = 'eng' 
      ..files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'screen.jpg'));

    try {
      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var jsonResponse = json.decode(responseData);
        if (jsonResponse['ParsedResults'] != null && jsonResponse['ParsedResults'].isNotEmpty) {
          return jsonResponse['ParsedResults'][0]['ParsedText'].toString().replaceAll('\r\n', ' ').trim();
        }
      }
    } catch (e) {
      debugPrint("OCR Hatası: $e");
    }
    return "";
  }

  Future<void> _translateWithDeepL(String text) async {
    if (_deepLApiKey == "SENIN_DEEPL_API_ANAHTARIN") return;

    final url = Uri.parse('https://api-free.deepl.com/v2/translate');
    
    try {
      final response = await http.post(
        url,
        headers: {'Authorization': 'DeepL-Auth-Key $_deepLApiKey'},
        body: {'text': text, 'target_lang': 'TR'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _originalText = text;
            _translatedText = data['translations'][0]['text'];
            _detectedLang = data['translations'][0]['detected_source_language'];
          });
        }
      }
    } catch (e) {
      debugPrint("DeepL Hatası: $e");
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DragToMoveArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), 
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4), 
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.gamepad, color: Colors.blueAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            "PS Remote Play Bağlantısı Aktif | Dil: ${_detectedLang.isEmpty ? '?' : _detectedLang}",
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _translatedText,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _originalText,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
