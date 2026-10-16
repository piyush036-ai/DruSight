/// The presumptive-result disclaimer (master spec section 1).
///
/// Shown on every result and report surface. Not dismissible, not collapsible.
library;

import 'package:flutter/material.dart';

import '../config/app_config.dart';

class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        border: Border.all(color: const Color(0xFFE0A030)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: Color(0xFF8A5B00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              AppConfig.presumptiveDisclaimer,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5A3D00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
