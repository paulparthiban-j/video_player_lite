import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/scan_directory_service.dart';

class ScanDirectoriesSettingsScreen extends StatefulWidget {
  const ScanDirectoriesSettingsScreen({super.key});

  @override
  State<ScanDirectoriesSettingsScreen> createState() =>
      _ScanDirectoriesSettingsScreenState();
}

class _ScanDirectoriesSettingsScreenState
    extends State<ScanDirectoriesSettingsScreen> {
  List<String> _allDirectories = [];
  List<String> _customDirectories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allDirs = await ScanDirectoryService.getAllScanDirectories();
      final customDirs = await ScanDirectoryService.getCustomDirectories();

      setState(() {
        _allDirectories = allDirs;
        _customDirectories = customDirs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading directories: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _addDirectory() async {
    final String? selectedDirectory =
        await ScanDirectoryService.pickDirectory();

    if (selectedDirectory != null && mounted) {
      // Show loading dialog
      unawaited(
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Validating directory...'),
              ],
            ),
          ),
        ),
      );

      try {
        // Validate directory
        final isValid = await ScanDirectoryService.validateDirectory(
          selectedDirectory,
        );

        // Close loading dialog
        if (mounted) Navigator.pop(context);

        if (!isValid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Directory is not accessible or does not exist'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Add directory
        final success = await ScanDirectoryService.addCustomDirectory(
          selectedDirectory,
        );

        if (success) {
          unawaited(HapticFeedback.lightImpact());
          await _loadDirectories();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Added: ${ScanDirectoryService.getDisplayName(selectedDirectory)}',
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Directory already exists in scan list'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.pop(context);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding directory: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _removeDirectory(String directoryPath) async {
    final isDefault = ScanDirectoryService.isDefaultDirectory(directoryPath);

    if (isDefault) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot remove default scan directories'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirmed = await _showConfirmDialog(
      'Remove Directory',
      'Are you sure you want to remove this directory from the scan list?\n\n${ScanDirectoryService.getDisplayName(directoryPath)}',
    );

    if (!confirmed) return;

    try {
      final success = await ScanDirectoryService.removeCustomDirectory(
        directoryPath,
      );

      if (success) {
        unawaited(HapticFeedback.lightImpact());
        await _loadDirectories();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed: ${ScanDirectoryService.getDisplayName(directoryPath)}',
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing directory: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await _showConfirmDialog(
      'Reset to Defaults',
      'This will remove all custom directories and keep only the default scan directories. Continue?',
    );

    if (!confirmed) return;

    try {
      final success = await ScanDirectoryService.resetToDefaults();

      if (success) {
        unawaited(HapticFeedback.mediumImpact());
        await _loadDirectories();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Reset to default directories'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resetting: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Scan Directories'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          if (_customDirectories.isNotEmpty)
            IconButton(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restore),
              tooltip: 'Reset to Defaults',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Info Card
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Scan Directories',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'These directories are scanned for video files. Default directories cannot be removed, but you can add custom directories.',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Directories List (bottom padding clears the FAB and the
                // gesture navigation bar).
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    96 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList.builder(
                    itemCount: _allDirectories.length,
                    itemBuilder: (context, index) {
                      final directory = _allDirectories[index];
                      final isDefault = ScanDirectoryService.isDefaultDirectory(
                        directory,
                      );
                      final displayName = ScanDirectoryService.getDisplayName(
                        directory,
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDefault
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  )
                                : theme.dividerColor,
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isDefault ? Icons.folder_special : Icons.folder,
                            color: isDefault
                                ? theme.colorScheme.primary
                                : theme.iconTheme.color,
                          ),
                          title: Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: isDefault
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          subtitle: isDefault
                              ? Text(
                                  'Default directory',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          trailing: !isDefault
                              ? IconButton(
                                  onPressed: () => _removeDirectory(directory),
                                  icon: Icon(
                                    Icons.remove_circle_outline,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  tooltip: 'Remove',
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDirectory,
        backgroundColor: theme.colorScheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Directory',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
