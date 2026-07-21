import 'package:flutter/material.dart';

import '../../../core/constants/app_text_styles.dart';

/// Labelled text field wrapping the themed [TextFormField].
class AppTextField extends StatelessWidget {
  /// Optional built-in label. Omit it when the caller renders its own label
  /// (e.g. a [FieldLabel]) above the field.
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final int? maxLength;
  final bool autofocus;
  final Widget? suffix;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final int? minLines;

  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.autofocus = false,
    this.suffix,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(label!, style: AppTextStyles.label),
          ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          maxLength: maxLength,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          maxLines: obscure ? 1 : maxLines,
          minLines: minLines,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
