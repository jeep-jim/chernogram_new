import 'dart:convert';

import 'package:flutter/material.dart';

import 'brand.dart';

// Compatibility fallback for the deterministic legacy build patch. Direct
// call handlers use their local callerAvatar value; the group-call dialog may
// safely fall back to its icon when the legacy patch does not inject one.
String? callerAvatar;

class CgCallAvatar extends StatelessWidget {
  final String? avatarBase64;
  final String name;
  final double size;
  final IconData fallbackIcon;

  const CgCallAvatar({
    super.key,
    required this.avatarBase64,
    required this.name,
    this.size = 92,
    this.fallbackIcon = Icons.person_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final raw = avatarBase64;
    if (raw != null && raw.isNotEmpty) {
      try {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .28),
                blurRadius: 24,
              ),
            ],
            image: DecorationImage(
              image: MemoryImage(base64Decode(raw)),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {}
    }
    final letter = name.trim().isEmpty ? '' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C5CFF), Color(0xFF18B8FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: ChernogramColors.orange.withValues(alpha: .30),
            blurRadius: 24,
          ),
        ],
      ),
      child: letter.isEmpty
          ? Icon(fallbackIcon, color: Colors.white, size: size * .44)
          : Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * .38,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}
