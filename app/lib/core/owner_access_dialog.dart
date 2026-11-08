import 'package:flutter/material.dart';

import 'owner_auth_service.dart';

class OwnerAccessDialog extends StatefulWidget {
  const OwnerAccessDialog({
    super.key,
    this.authService,
  });

  /// Optional service override for tests. Production uses the secure singleton.
  final OwnerAuthService? authService;

  @override
  State<OwnerAccessDialog> createState() => _OwnerAccessDialogState();
}

class _OwnerAccessDialogState extends State<OwnerAccessDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _configured = false;
  bool _loading = true;
  bool _working = false;
  bool _showPassword = false;
  String? _error;

  OwnerAuthService get _auth => widget.authService ?? OwnerAuthService.instance;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    try {
      final configured = await _auth.isPasswordConfigured();

      if (!mounted) return;

      setState(() {
        _configured = configured;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Secure storage is unavailable on this device.';
      });
    }
  }

  Future<void> _submit() async {
    final password = _passwordController.text;

    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }

    if (!_configured) {
      if (password.length < 10) {
        setState(
          () => _error = 'Use at least 10 characters for your password.',
        );
        return;
      }

      if (password != _confirmController.text) {
        setState(() => _error = 'The passwords do not match.');
        return;
      }
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      if (_configured) {
        final success = await _auth.authenticateOwner(password);

        if (!success) {
          if (mounted) {
            setState(() {
              _working = false;
              _error = 'Incorrect password. Please try again.';
            });
          }
          return;
        }
      } else {
        await _auth.setOwnerPassword(password);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Could not complete owner authentication.';
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_configured ? 'Owner login' : 'Set up owner access'),
      content: _loading
          ? const SizedBox(
              height: 70,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _configured
                      ? 'Enter the private owner password to open this section.'
                      : 'Create a private password for access to business '
                          'financial information.',
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Owner password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _showPassword = !_showPassword,
                      ),
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (_configured) _submit();
                  },
                ),
                if (!_configured) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showPassword,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: _working || _loading
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading || _working ? null : _submit,
          child: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_configured ? 'Unlock' : 'Create password'),
        ),
      ],
    );
  }
}
