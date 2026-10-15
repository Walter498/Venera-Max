import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:venera/network/qingman.dart';

/// Standalone public route; settings/navigation owners may push this widget.
class QingmanProfilePage extends StatefulWidget {
  const QingmanProfilePage({super.key});
  @override
  State<QingmanProfilePage> createState() => _QingmanProfilePageState();
}

class _QingmanProfilePageState extends State<QingmanProfilePage> {
  bool _busy = true;
  bool _installed = false;
  String _message = '正在检查本机配置…';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await qingmanTransport.profileStatus();
    if (!mounted) return;
    setState(() {
      _installed = status['installed'] == true;
      _message = _installed ? '本机配置已导入（版本 1）' :
          (status['error'] as String? ?? '尚未导入配置');
      _busy = false;
    });
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: '青漫配置', extensions: ['qmprofile', 'json'],
          uniformTypeIdentifiers: ['public.data']),
      ]);
      if (file == null) return;
      if (await file.length() > QingmanTransport.maxProfileBytes) {
        throw const QingmanException('profile');
      }
      final bytes = await file.readAsBytes();
      try {
        await qingmanTransport.importProfile(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _message = const QingmanException('profile').toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: const Text('清除青漫配置？'),
        content: const Text('将删除本机配置并使内存中的访问令牌失效。原始导入文件不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await qingmanTransport.clearProfile();
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _message = const QingmanException('profile').toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('青漫本机配置')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.verified_user_outlined, size: 48),
      const SizedBox(height: 16),
      Text(_message, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      const Text('从可信来源导入 .qmprofile 文件。配置只保存在应用私有数据目录，不会打包进漫画源或发送给 JavaScript。导入仅验证配置与证书可读取，不代表网络服务已验证。'),
      const SizedBox(height: 12),
      const Text('文件包含客户端身份与密钥，请勿公开、提交到仓库或通过不可信渠道分享。导入后建议自行删除下载目录中的原文件。更换配置会清除内存令牌；清除配置仍保留本机随机设备标识。'),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _busy ? null : _import,
        icon: const Icon(Icons.file_open_outlined),
        label: Text(_installed ? '替换配置' : '导入配置')),
      if (_installed) TextButton(onPressed: _busy ? null : _clear, child: const Text('清除本机配置')),
      if (_busy) const Center(child: Padding(padding: EdgeInsets.all(16),
        child: CircularProgressIndicator())),
    ]),
  );
}
