import 'dart:convert';

import 'package:flutter/material.dart';

class PanelProfileAvatar extends StatefulWidget {
  const PanelProfileAvatar({
    super.key,
    required this.size,
    required this.imageBase64,
    required this.fallback,
    required this.fallbackFontSize,
    required this.backgroundColor,
  });

  final double size;
  final String? imageBase64;
  final String fallback;
  final double fallbackFontSize;
  final Color backgroundColor;

  @override
  State<PanelProfileAvatar> createState() => _PanelProfileAvatarState();
}

class _PanelProfileAvatarState extends State<PanelProfileAvatar> {
  ImageProvider? _imageProvider;

  @override
  void initState() {
    super.initState();
    _updateImageProvider();
  }

  @override
  void didUpdateWidget(covariant PanelProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBase64 != widget.imageBase64) {
      _updateImageProvider();
    }
  }

  void _updateImageProvider() {
    final encoded = widget.imageBase64;
    if (encoded == null || encoded.isEmpty) {
      _imageProvider = null;
      return;
    }
    try {
      _imageProvider = MemoryImage(base64Decode(encoded));
    } on FormatException {
      _imageProvider = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = _imageProvider;
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: imageProvider == null
            ? _buildFallback()
            : Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildFallback(),
              ),
      ),
    );
  }

  Widget _buildFallback() => ColoredBox(
    color: widget.backgroundColor,
    child: Center(
      child: Text(
        widget.fallback,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.fallbackFontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
