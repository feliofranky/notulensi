import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _obscureKey = true;
  String _selectedModel = StorageService.defaultModel;
  int _selectedSampleRate = 16000;

  bool _isTesting = false;
  String? _testMessage;
  bool _testSuccess = false;
  bool _isLoading = true;

  final List<Map<String, String>> _availableModels = [
    {
      'id': 'gemini-2.0-flash-lite',
      'name': 'Gemini 2.0 Flash-Lite (Direkomendasikan)',
      'desc': 'Sangat cepat, hemat kuota, mendukung multimodal audio langsung.',
    },
    {
      'id': 'gemini-2.0-flash',
      'name': 'Gemini 2.0 Flash',
      'desc': 'Model generasi baru dengan kapabilitas penalaran audio tinggi.',
    },
    {
      'id': 'gemini-1.5-flash',
      'name': 'Gemini 1.5 Flash',
      'desc': 'Model klasik yang stabil dengan konteks hingga 1 juta token.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await StorageService.getApiKey();
    final model = await StorageService.getModel();
    final rate = await StorageService.getSampleRate();

    setState(() {
      _apiKeyController.text = key;
      _selectedModel = model;
      _selectedSampleRate = rate;
      _isLoading = false;
    });
  }

  Future<void> _testConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan API Key terlebih dahulu.')),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    try {
      await GeminiService.testApiKey(key, model: _selectedModel);
      setState(() {
        _testSuccess = true;
        _testMessage = '✓ Koneksi Berhasil! API Key aktif & terhubung ke Google Gemini.';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = '✗ Gagal: ${e.toString().replaceAll("Exception: ", "")}';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    await StorageService.setApiKey(_apiKeyController.text.trim());
    await StorageService.setModel(_selectedModel);
    await StorageService.setSampleRate(_selectedSampleRate);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          content: Text('Pengaturan berhasil disimpan!'),
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
        title: const Text('Pengaturan HerzNote'),
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
                  const Text(
                    'GOOGLE GEMINI API KEY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181B21),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF262A34)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Masukkan 1 API Key Gemini milik Anda. HerzNote akan menggunakan API ini untuk menganalisis rekaman rapat.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: _obscureKey,
                          style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'AIzaSy...',
                            hintStyle: const TextStyle(color: Color(0xFF475569)),
                            filled: true,
                            fillColor: const Color(0xFF0F1115),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF10B981)),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureKey ? Icons.visibility_off : Icons.visibility,
                                color: const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureKey = !_obscureKey;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                  : const Icon(Icons.flash_on, size: 16),
                              label: Text(_isTesting ? 'Menguji...' : 'Uji Koneksi'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF262A34),
                                foregroundColor: const Color(0xFFF1F5F9),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                        if (_testMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _testSuccess ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _testSuccess ? Icons.check_circle : Icons.error,
                                  color: _testSuccess ? const Color(0xFF34D399) : const Color(0xFFF87171),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _testMessage!,
                                    style: TextStyle(
                                      color: _testSuccess ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // MODEL SELECTION SECTION
                  const Text(
                    'PILIHAN ENGINE GEMINI AI',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF181B21),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF262A34)),
                    ),
                    child: Column(
                      children: _availableModels.map((m) {
                        final isSelected = _selectedModel == m['id'];
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedModel = m['id']!;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: m == _availableModels.last ? Colors.transparent : const Color(0xFF262A34),
                                ),
                              ),
                            ),
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
                                const SizedBox(width: 8),
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

                  // AUDIO QUALITY
                  const Text(
                    'KUALITAS REKAMAN AUDIO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181B21),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF262A34)),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<int>(
                          value: 16000,
                          groupValue: _selectedSampleRate,
                          title: const Text('16 kHz Mono (Sangat Direkomendasikan)', style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 14)),
                          subtitle: const Text('Format optimal untuk suara percakapan manusia. File sangat ringkas (~17MB per 1 jam rapat) dan langsung muat dalam limit Gemini.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          activeColor: const Color(0xFF10B981),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedSampleRate = val);
                          },
                        ),
                        const Divider(color: Color(0xFF262A34)),
                        RadioListTile<int>(
                          value: 44100,
                          groupValue: _selectedSampleRate,
                          title: const Text('44.1 kHz Studio', style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 14)),
                          subtitle: const Text('Kualitas tinggi untuk ruangan besar atau banyak peserta (~45MB per jam).', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          activeColor: const Color(0xFF10B981),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedSampleRate = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // SAVE BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
