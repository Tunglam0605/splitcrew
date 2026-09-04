import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'app_state.dart';
import 'sync_service.dart';

final class JoinCrewPage extends StatefulWidget {
  const JoinCrewPage({super.key, required this.sync});

  final MobileSyncController sync;

  @override
  State<JoinCrewPage> createState() => _JoinCrewPageState();
}

final class _JoinCrewPageState extends State<JoinCrewPage> {
  final _inviteController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final invite = _inviteController.text.trim();
    if (invite.isEmpty) {
      _showError('Paste the SplitCrew invite from the owner first.');
      return;
    }
    setState(() => _joining = true);
    try {
      await widget.sync.joinFromInvite(invite);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError('$error');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a crew')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Same-network join', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text(
                    'Keep the owner phone and this phone on the same Wi-Fi or hotspot. The owner must keep Host Session running while members are connected.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _inviteController,
            minLines: 4,
            maxLines: 8,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'SplitCrew invite',
              hintText: 'splitcrew://join/…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _joining
                ? null
                : () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) _inviteController.text = data!.text!;
                  },
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('Paste from clipboard'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _joining ? null : _join,
            icon: const Icon(Icons.group_add_rounded),
            label: Text(_joining ? 'Joining…' : 'Join crew'),
          ),
          const SizedBox(height: 18),
          const Text(
            'QR scanning will be added after this two-device LAN flow is validated. The owner already receives a QR and copyable invite payload.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

final class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({
    super.key,
    required this.controller,
    required this.sync,
  });

  final TripController controller;
  final MobileSyncController sync;

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

final class _SyncCenterPageState extends State<SyncCenterPage> {
  String? _selectedMemberId;
  String? _invite;

  List<StoredMember> get _inviteMembers =>
      widget.controller.trip?.members.where((member) => !member.isOwner).toList() ?? const [];

  Future<void> _startHost() async {
    try {
      await widget.sync.startHost();
      if (!mounted) return;
      final members = _inviteMembers;
      if (members.isNotEmpty) setState(() => _selectedMemberId ??= members.first.id);
    } catch (error) {
      if (mounted) _error('$error');
    }
  }

  Future<void> _stopHost() async {
    try {
      await widget.sync.stopHost();
      if (mounted) setState(() => _invite = null);
    } catch (error) {
      if (mounted) _error('$error');
    }
  }

  void _generateInvite() {
    final memberId = _selectedMemberId;
    if (memberId == null) {
      _error('Add a non-owner member first.');
      return;
    }
    try {
      setState(() => _invite = widget.sync.createInviteForMember(memberId));
    } catch (error) {
      _error('$error');
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crew sync')),
      body: AnimatedBuilder(
        animation: widget.sync,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _StatusCard(sync: widget.sync, controller: widget.controller),
              const SizedBox(height: 16),
              if (widget.sync.mode == MobileSyncMode.member)
                _MemberSessionCard(sync: widget.sync, controller: widget.controller)
              else ...[
                _HostControlCard(
                  sync: widget.sync,
                  onStart: _startHost,
                  onStop: _stopHost,
                ),
                if (widget.sync.isHostRunning) ...[
                  const SizedBox(height: 16),
                  _InviteCard(
                    members: _inviteMembers,
                    selectedMemberId: _selectedMemberId,
                    onChanged: (value) => setState(() {
                      _selectedMemberId = value;
                      _invite = null;
                    }),
                    onGenerate: _generateInvite,
                    invite: _invite,
                  ),
                ],
              ],
              if (widget.sync.lastError != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(widget.sync.lastError!),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Current validation transport uses REST polling every 2 seconds. The host remains authoritative; clients refresh a canonical snapshot after committed revisions. WebSocket push and offline pending-operation queues are the next hardening slice.',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sync, required this.controller});

  final MobileSyncController sync;
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final modeText = switch (sync.mode) {
      MobileSyncMode.local => 'Local only',
      MobileSyncMode.host => 'Owner host',
      MobileSyncMode.member => 'Member client',
    };
    final icon = switch (sync.mode) {
      MobileSyncMode.local => Icons.phone_android_rounded,
      MobileSyncMode.host => Icons.router_rounded,
      MobileSyncMode.member => sync.memberOnline ? Icons.sync_rounded : Icons.sync_problem_rounded,
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(modeText),
        subtitle: Text(
          'Crew revision ${sync.mode == MobileSyncMode.member ? sync.canonicalRevision : controller.trip?.version ?? 0}',
        ),
        trailing: sync.busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      ),
    );
  }
}

final class _HostControlCard extends StatelessWidget {
  const _HostControlCard({
    required this.sync,
    required this.onStart,
    required this.onStop,
  });

  final MobileSyncController sync;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final running = sync.isHostRunning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Owner Host Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              running
                  ? 'Members on the same LAN can now join this phone.'
                  : 'Start an explicit local server on this phone. Nothing is exposed to the Internet by SplitCrew.',
            ),
            if (running) ...[
              const SizedBox(height: 12),
              SelectableText('Endpoint: http://${sync.advertisedHost}:${sync.hostPort}'),
              const SizedBox(height: 4),
              SelectableText('Host ID: ${sync.hostId}'),
            ],
            const SizedBox(height: 14),
            if (running)
              OutlinedButton.icon(
                onPressed: sync.busy ? null : onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop Host Session'),
              )
            else
              FilledButton.icon(
                onPressed: sync.busy ? null : onStart,
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Start Host Session'),
              ),
          ],
        ),
      ),
    );
  }
}

final class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.members,
    required this.selectedMemberId,
    required this.onChanged,
    required this.onGenerate,
    required this.invite,
  });

  final List<StoredMember> members;
  final String? selectedMemberId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onGenerate;
  final String? invite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Invite a member', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Invites expire after 10 minutes and are single-use.'),
            const SizedBox(height: 12),
            if (members.isEmpty)
              const Text('Add a member to this crew before generating an invite.')
            else ...[
              DropdownButtonFormField<String>(
                initialValue: selectedMemberId ?? members.first.id,
                decoration: const InputDecoration(labelText: 'Member profile'),
                items: [
                  for (final member in members) DropdownMenuItem(value: member.id, child: Text(member.name)),
                ],
                onChanged: onChanged,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onGenerate,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Generate invite'),
              ),
            ],
            if (invite != null) ...[
              const SizedBox(height: 18),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: invite!, version: QrVersions.auto, size: 240),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(invite!, maxLines: 5),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied.')));
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy invite'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _MemberSessionCard extends StatelessWidget {
  const _MemberSessionCard({required this.sync, required this.controller});

  final MobileSyncController sync;
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final memberName = sync.memberId == null ? 'Unknown member' : controller.memberName(sync.memberId!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Member Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Profile: $memberName'),
            Text('Status: ${sync.memberOnline ? 'Connected' : 'Host unavailable'}'),
            Text('Canonical revision: ${sync.canonicalRevision}'),
            if (sync.pinnedHostId != null) SelectableText('Pinned host: ${sync.pinnedHostId}'),
            if (sync.lastSyncAt != null) Text('Last sync: ${sync.lastSyncAt}'),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: sync.busy
                  ? null
                  : () async {
                      try {
                        await sync.refreshMemberSnapshot();
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: sync.busy
                  ? null
                  : () async {
                      await sync.leaveMemberSession();
                      if (context.mounted) Navigator.of(context).pop();
                    },
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Leave sync session'),
            ),
          ],
        ),
      ),
    );
  }
}
