import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  String _rawApiKey = '';
  bool _isEditingKey = false;

  String _selectedModel = StorageService.defaultModel;
  int _selectedSampleRate = 16000;

  bool _isTesting = false;
  bool? _testSuccess;
  String? _testStatusText;
  bool _isLoading = true;

  final List<Map<String, String>> _availableModels = [
    {
      'id': 'gemini-3.5-flash-lite',
      'name': 'Gemini 3.5 Flash-Lite (Direkomendasikan)',
      'desc': 'Model paling cepat, hemat kuota, dan multimodal audio langsung.',
    },
    {
      'id': 'gemini-3.5-flash',
      'name': 'Gemini 3.5 Flash',
      'desc': 'Model dengan tingkat penalaran dan akurasi analisis lebih mendalam.',
    },
    {
      'id': 'gemini-3.5-transcribe',
      'name': 'Gemini 3.5 Transcribe',
      'desc': 'Model spesialis percakapan audio dan pemisahan pembicara.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  /// Sensor API Key: tampilkan maksimal 10 karakter awal, sisanya jadi titik tebal
  String _maskApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 10) {
      return '•' * trimmed.length;
    }
    final prefix = trimmed.substring(0, 10);
    return '$prefix••••••••••••••••••••••••';
  }

  Future<void> _loadSettings() async {
    final key = await StorageService.getApiKey();
    final model = await StorageService.getModel();
    final rate = await StorageService.getSampleRate();

    if (mounted) {
      setState(() {
        _rawApiKey = key;
        _isEditingKey = key.isEmpty;
        _apiKeyController.text = key.isEmpty ? '' : _maskApiKey(key);
        _selectedModel = model;
        _selectedSampleRate = rate;
        _isLoading = false;
      });
    }
  }

  void _handleKeyInputChanged(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      _rawApiKey = '';
      return;
    }

    // Jika user baru saja paste atau mengetik key utuh (belum mengandung bullet sensor)
    if (!trimmed.contains('•') && trimmed.length >= 16) {
      _rawApiKey = trimmed;
      final masked = _maskApiKey(trimmed);
      _apiKeyController.value = TextEditingValue(
        text: masked,
        selection: TextSelection.collapsed(offset: masked.length),
      );
      setState(() {
        _testSuccess = null;
        _testStatusText = null;
      });
    } else if (!trimmed.contains('•')) {
      _rawApiKey = trimmed;
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (pasted.isNotEmpty) {
      _rawApiKey = pasted;
      final masked = _maskApiKey(pasted);
      setState(() {
        _apiKeyController.value = TextEditingValue(
          text: masked,
          selection: TextSelection.collapsed(offset: masked.length),
        );
        _testSuccess = null;
        _testStatusText = null;
      });
    }
  }

  Future<void> _testConnection() async {
    final keyToTest = _rawApiKey.trim();
    if (keyToTest.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testStatusText = 'API Key kosong';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testStatusText = null;
    });

    try {
      await GeminiService.testApiKey(keyToTest, model: _selectedModel);
      if (mounted) {
        setState(() {
          _testSuccess = true;
          _testStatusText = 'Terhubung';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testSuccess = false;
          _testStatusText = 'Gagal terhubung';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    await StorageService.setApiKey(_rawApiKey.trim());
    await StorageService.setModel(_selectedModel);
    await StorageService.setSampleRate(_selectedSampleRate);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          content: Text('Pengaturan berhasil disimpan.'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        title: const Text(
          'Pengaturan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF181B21),
        foregroundColor: const Color(0xFFF1F5F9),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API KEY SECTION
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'GOOGLE GEMINI API KEY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181B21),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kunci API tersimpan secara lokal dan otomatis disensor demi keamanan.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        const SizedBox(height: 12),

                        // MODE TAMPILAN SENSOR (Read-only masked view)
                        if (!_isEditingKey && _rawApiKey.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F1115),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.key_outlined, size: 18, color: Color(0xFF10B981)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _maskApiKey(_rawApiKey),
                                    style: const TextStyle(
                                      color: Color(0xFFF1F5F9),
                                      fontSize: 14,
                                      fontFamily: 'monospace',
                                      letterSpacing: 0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isEditingKey = true;
                                      _apiKeyController.clear();
                                      _testSuccess = null;
                                      _testStatusText = null;
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Ganti Key',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // MODE GANTI KEY (Langsung tersensor begitu di-paste)
                          TextField(
                            controller: _apiKeyController,
                            onChanged: _handleKeyInputChanged,
                            style: const TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                            decoration: InputDecoration(
                              hintText: 'Tempel API Key baru di sini...',
                              hintStyle: const TextStyle(color: Color(0xFF475569), fontFamily: 'sans-serif'),
                              filled: true,
                              fillColor: const Color(0xFF0F1115),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Tempel dari Clipboard',
                                    icon: const Icon(Icons.paste_rounded, color: Color(0xFF10B981), size: 18),
                                    onPressed: _pasteFromClipboard,
                                  ),
                                  if (_apiKeyController.text.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Bersihkan',
                                      icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _apiKeyController.clear();
                                          _rawApiKey = '';
                                          _testSuccess = null;
                                          _testStatusText = null;
                                        });
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // TOMBOL UJI KONEKSI + STATUS INLINE SEBELAH KANAN
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isTesting ? null : _testConnection,
                              icon: _isTesting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.bolt, size: 16),
                              label: Text(_isTesting ? 'Menguji...' : 'Uji Koneksi'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF262A34),
                                foregroundColor: const Color(0xFFF1F5F9),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            if (_testSuccess != null && _testStatusText != null) ...[
                              const SizedBox(width: 12),
                              Icon(
                                _testSuccess! ? Icons.check_circle : Icons.cancel,
                                color: _testSuccess! ? const Color(0xFF10B981) : const Color(0xFFF87171),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _testStatusText!,
                                  style: TextStyle(
                                    color: _testSuccess! ? const Color(0xFF10B981) : const Color(0xFFF87171),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // MODEL SELECTION SECTION
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'PILIHAN ENGINE AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF181B21),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: _availableModels.map((m) {
                        final isSelected = _selectedModel == m['id'];
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              _selectedModel = m['id']!;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Radio<String>(
                                  value: m['id']!,
                                  groupValue: _selectedModel,
                                  activeColor: const Color(0xFF10B981),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedModel = val;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m['name']!,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        m['desc']!,
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // AUDIO QUALITY SECTION
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'KUALITAS REKAMAN AUDIO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181B21),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<int>(
                          value: 16000,
                          groupValue: _selectedSampleRate,
                          title: const Text(
                            '16 kHz Mono (Direkomendasikan)',
                            style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Optimal untuk suara percakapan manusia. File sangat ringkas (~17MB/jam) dan unggah cepat.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                          activeColor: const Color(0xFF10B981),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedSampleRate = val);
                          },
                        ),
                        const SizedBox(height: 6),
                        RadioListTile<int>(
                          value: 44100,
                          groupValue: _selectedSampleRate,
                          title: const Text(
                            '44.1 kHz Studio',
                            style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Kualitas tinggi untuk ruangan besar atau banyak peserta (~45MB/jam).',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                          activeColor: const Color(0xFF10B981),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedSampleRate = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // SAVE BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Simpan Pengaturan',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
