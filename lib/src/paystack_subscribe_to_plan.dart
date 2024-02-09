// ignore_for_file: prefer_typing_uninitialized_variables

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

/// Subscribe to a plan with Paystack provided you have you Paystack:
/// secret [secretKey], [email], [planId] and [amount].
class PaystackSubscribeToPlan extends StatefulWidget {
  /// Secret Key is provided by Paystack when an account is created with PayStack.
  final String secretKey;

  /// Email of the customer trying to make payment.
  final String email;

  /// This is the plan ID from Paystack Dashboard.
  /// It is a unique identifier for the plan.
  final String planId;

  /// This is the amount as a rounded figure.
  /// Do not include the currency symbol, or decimal places.
  final String amount;

  /// If transacted was completed successfully.
  final Function? transactionCompleted;

  /// If transacted was not completed at all.
  final Function? transactionNotCompleted;

  ///for sending user back
  final BuildContext? context;

  const PaystackSubscribeToPlan(
      {Key? key,
      required this.secretKey,
      required this.email,
      required this.amount,
      required this.planId,
      required this.transactionCompleted,
      required this.transactionNotCompleted,
      this.context})
      : super(key: key);

  @override
  State<PaystackSubscribeToPlan> createState() => _PaystackPayNowState();
}

class _PaystackPayNowState extends State<PaystackSubscribeToPlan> {
  /// Adds two extra zeroes to the amount to denote decimal places.
  /// Example: 1000 => 100000 which is 1000.00
  String _addTwoExtraZeroes(String amount) {
    return "${amount}00";
  }

  /// Makes HTTP Request to Paystack for access to make payment.
  Future<PaystackRequestResponse> _makePaymentRequest() async {
    var response;
    try {
      /// Sending Data to paystack.
      response = await http.post(
        /// Url to send data to
        Uri.parse('https://api.paystack.co/transaction/initialize'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.secretKey}',
        },

        /// Data to send to the URL.
        body: jsonEncode({
          "email": widget.email,
          "amount": _addTwoExtraZeroes(widget.amount),
          "plan": widget.amount,
        }),
      );
    } on Exception catch (e) {
      /// In the event of an exception, take the user back and show a SnackBar error.
      throw Exception(
          "Response Code: ${response.statusCode}, Response Body${e.toString()}");
    }

    if (response.statusCode == 200) {
      /// Response code 200 means OK.
      /// Send data to the POJO Class if 200.
      return PaystackRequestResponse.fromJson(jsonDecode(response.body));
    } else {
      /// Anything else means there is an issue.
      throw Exception(
          "Response Code: ${response.statusCode}, Response Body${response.body}");
    }
  }

  /// Checks for transaction status of current transaction before view closes.
  Future<bool> _checkTransactionStatusSuccessful(String ref) async {
    var response;
    try {
      /// Getting data, passing [ref] as a value to the URL that is being requested.
      response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$ref'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.secretKey}',
        },
      );
    } on Exception catch (e) {
      /// In the event of an exception, take the user back and show a SnackBar error.
      throw Exception(
          "Response Code: ${response.statusCode}, Response Body${e.toString()}");
    }
    if (response.statusCode == 200) {
      /// Response code 200 means OK.
      var decodedRespBody = jsonDecode(response.body);
      if (decodedRespBody["data"]["gateway_response"] == "Approved" ||
          decodedRespBody["data"]["gateway_response"] == "Successful") {
        return true;
      } else {
        return false;
      }
    } else {
      /// Anything else means there is an issue
      throw Exception(
          "Response Code: ${response.statusCode}, Response Body${response.body}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<PaystackRequestResponse>(
          future: _makePaymentRequest(),
          builder: (context, AsyncSnapshot<PaystackRequestResponse> snapshot) {
            /// Show screen if snapshot has data and status is true.
            if (snapshot.hasData && snapshot.data!.status == true) {
              final controller = WebViewController()
                ..setJavaScriptMode(JavaScriptMode.unrestricted)
                ..setUserAgent("Flutter;Webview")
                ..setNavigationDelegate(
                  NavigationDelegate(
                    onNavigationRequest: (request) async {
                      if (request.url.contains('cancelurl.com')) {
                        await _checkTransactionStatusSuccessful(
                                snapshot.data!.reference)
                            .then((value) {
                          if (value == true) {
                            widget.transactionCompleted?.call();
                            Navigator.of(widget.context!).pop(); //close webview
                          } else {
                            widget.transactionNotCompleted?.call();
                            Navigator.of(widget.context!).pop(); //close webview
                          }
                        });
                      } else if (request.url.contains('paystack.co/close')) {
                        await _checkTransactionStatusSuccessful(
                                snapshot.data!.reference)
                            .then((value) {
                          if (value == true) {
                            widget.transactionCompleted?.call();
                            Navigator.of(context).pop(); //close webview
                          } else {
                            widget.transactionNotCompleted?.call();
                            Navigator.of(widget.context!).pop(); //close webview
                          }
                        });
                      }
                      if (request.url == "https://hello.pstk.xyz/callback") {
                        await _checkTransactionStatusSuccessful(
                                snapshot.data!.reference)
                            .then((value) {
                          if (value == true) {
                            widget.transactionCompleted?.call();
                            Navigator.of(widget.context!).pop(); //close webview
                          } else {
                            widget.transactionNotCompleted?.call();
                            Navigator.of(widget.context!).pop(); //close webview
                          }
                        });
                      }
                      return NavigationDecision.navigate;
                    },
                  ),
                )
                ..loadRequest(Uri.parse(snapshot.data!.authUrl));
              return WebViewWidget(
                controller: controller,
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('${snapshot.error}'),
              );
            }

            return const Center(
              child: CircularProgressIndicator(),
            );
          },
        ),
      ),
    );
  }
}

/// Request Response POJO Class for recieving data
/// from the paystack API.
class PaystackRequestResponse {
  final bool status;
  final String authUrl;
  final String reference;

  const PaystackRequestResponse(
      {required this.authUrl, required this.status, required this.reference});

  factory PaystackRequestResponse.fromJson(Map<String, dynamic> json) {
    return PaystackRequestResponse(
      status: json['status'],
      authUrl: json['data']["authorization_url"],
      reference: json['data']["reference"],
    );
  }
}
