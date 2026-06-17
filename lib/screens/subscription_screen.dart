import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;
  bool _isLoadingPrice = true;
  double? _price;
  String? _currency;
  String? _reference;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final countryCode = locale.countryCode ?? 'US';

      final response = await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/getSubscriptionPrice'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'countryCode': countryCode}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _price = (data['amount'] as num).toDouble();
          _currency = data['currency'] ?? 'USD';
          _isLoadingPrice = false;
        });
      } else {
        setState(() {
          _price = 10;
          _currency = 'USD';
          _isLoadingPrice = false;
        });
      }
    } catch (e) {
      setState(() {
        _price = 10;
        _currency = 'USD';
        _isLoadingPrice = false;
      });
    }
  }

  String _formatPrice() {
    if (_price == null) return '...';
    switch (_currency) {
      case 'NGN':
        return '₦${_price!.toInt()}';
      case 'EUR':
        return '€${_price!.toStringAsFixed(2)}';
      case 'GBP':
        return '£${_price!.toStringAsFixed(2)}';
      case 'USD':
        return '\$${_price!.toStringAsFixed(2)}';
      case 'CAD':
        return 'C\$${_price!.toStringAsFixed(2)}';
      default:
        return '${_currency ?? ""} ${_price!.toStringAsFixed(2)}';
    }
  }

  Future<void> _subscribe() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      // Initialize payment via Cloud Function
      final response = await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/initializePayment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'email': user.email,
          'amount': _price,
          'currency': _currency ?? 'NGN',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final authUrl = data['authorizationUrl'] as String;
        _reference = data['reference'] as String;

        // Open Paystack in webview
        if (mounted) {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => _PaystackWebView(
                url: authUrl,
                reference: _reference!,
              ),
            ),
          );

          if (result == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Subscription activated!')),
              );
              Navigator.of(context).pop();
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Payment initialization failed. Please try again.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('GigsCourt Premium',
            style:
                TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: _isLoadingPrice
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.verified, size: 64, color: AppColors.accent),
                    const SizedBox(height: 16),
                    const Text('Unlock Premium',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    const Text('Get unlimited visibility and more clients',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accent, width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(_formatPrice(),
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 36,
                                  color: AppColors.textPrimary)),
                          const Text('per 30 days',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 20),
                          _buildBenefit('Unlimited client leads'),
                          _buildBenefit('Verified badge on your profile'),
                          _buildBenefit('Priority ranking in search'),
                          _buildBenefit('Appear in Featured section'),
                          _buildBenefit('Online status visible to clients'),
                        ],
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _subscribe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Subscribe Now',
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Cancel anytime. Renews every 30 days.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBenefit(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14))),
        ],
      ),
    );
  }
}

class _PaystackWebView extends StatefulWidget {
  final String url;
  final String reference;

  const _PaystackWebView({required this.url, required this.reference});

  @override
  State<_PaystackWebView> createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<_PaystackWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            // Detect if payment was successful
            if (url.contains('paystack.com') && url.contains('success')) {
              _verifyAndClose();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _verifyAndClose() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse(
            'https://us-central1-gigs-court.cloudfunctions.net/verifyPayment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'reference': widget.reference}),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Payment',
            style:
                TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}