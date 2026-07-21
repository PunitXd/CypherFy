import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// A 6-box numeric OTP field. No external package: a single transparent
/// [TextField] captures input (and system autofill/paste), while the boxes
/// underneath render the digits. Tapping anywhere focuses the field.
class OtpInput extends StatefulWidget {
  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  /// Fired once when the last digit is entered — handy to auto-submit.
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  const OtpInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.autofocus = true,
  });

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {}); // repaint the boxes
    final v = widget.controller.text;
    widget.onChanged?.call(v);
    if (v.length == widget.length) {
      _focus.unfocus();
      widget.onCompleted?.call(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (i) {
              final filled = i < text.length;
              final active = i == text.length && _focus.hasFocus;
              return Container(
                width: 48,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? AppColors.primary
                        : filled
                            ? AppColors.borderStr
                            : AppColors.border,
                    width: active ? 1.5 : 0.5,
                  ),
                ),
                child: Text(
                  filled ? text[i] : '',
                  style: AppTextStyles.code.copyWith(letterSpacing: 0),
                ),
              );
            }),
          ),
          // Transparent capture layer — invisible but receives taps + keyboard.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                showCursor: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
