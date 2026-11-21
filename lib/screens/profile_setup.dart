import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/side_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';

const List<String> _weightClasses = [
  '59',
  '66',
  '74',
  '83',
  '93',
  '105',
  '120',
  '120+',
];

/// Profile setup / edit form. Kilos are the stored truth: when the units
/// toggle is lb, the fields show lb and are converted back to kg on save.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirestoreService();
  final _auth = AuthService();

  final _nameController = TextEditingController();
  final _countryController = TextEditingController();
  final _gymController = TextEditingController();
  final _bodyweightController = TextEditingController();
  final _squatController = TextEditingController();
  final _benchController = TextEditingController();
  final _deadliftController = TextEditingController();

  String _sex = 'male';
  DateTime? _dob;
  String _units = 'kg';
  double _barWeightKg = 20.0;
  String _plateSet = 'calibrated';
  String? _weightClassLabel;

  /// How the user uses Forge — one or both. The app opens on the
  /// training side when they train; switchable anytime from the small
  /// pill at the top of the screen.
  bool _trains = true;
  bool _coaches = false;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  UserProfile? _existing;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final uid = _auth.currentUid;
    UserProfile? profile;
    if (uid != null) {
      try {
        profile = await _firestore.getProfile(uid);
      } catch (_) {
        profile = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _existing = profile;
      _loading = false;
      if (profile != null) {
        _units = profile.units;
        _sex = profile.sex;
        _dob = profile.dob;
        _barWeightKg = profile.barWeightKg;
        _plateSet = profile.plateSet;
        _trains = profile.trains;
        _coaches = profile.coaches;
        _nameController.text = profile.displayName;
        _countryController.text = profile.country;
        _gymController.text = profile.homeGym;
        if (profile.weightClassKg != null) {
          _weightClassLabel =
              _weightClasses.contains(profile.weightClassKg!.toStringAsFixed(0))
                  ? profile.weightClassKg!.toStringAsFixed(0)
                  : null;
        }
        _bodyweightController.text = _displayWeight(profile.bodyweightKg);
        _squatController.text =
            _displayWeight(profile.mainLifts['squat']);
        _benchController.text =
            _displayWeight(profile.mainLifts['bench']);
        _deadliftController.text =
            _displayWeight(profile.mainLifts['deadlift']);
      }
      // Prefill the known 1RMs when a lift is empty.
      if (_squatController.text.isEmpty) {
        _squatController.text = _displayWeight(180);
      }
      if (_benchController.text.isEmpty) {
        _benchController.text = _displayWeight(120);
      }
      if (_deadliftController.text.isEmpty) {
        _deadliftController.text = _displayWeight(200);
      }
    });
  }

  String _displayWeight(double? kg) {
    if (kg == null) return '';
    final value = _units == 'lb' ? StrengthMath.kgToLb(kg) : kg;
    return _trimNumber(value);
  }

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  double? _parseDisplayWeight(String text) {
    final value = double.tryParse(text.trim());
    if (value == null) return null;
    return _units == 'lb' ? StrengthMath.lbToKg(value) : value;
  }

  void _onUnitsChanged(String units) {
    if (units == _units) return;
    final bwKg = _parseDisplayWeight(_bodyweightController.text);
    final squatKg = _parseDisplayWeight(_squatController.text);
    final benchKg = _parseDisplayWeight(_benchController.text);
    final deadKg = _parseDisplayWeight(_deadliftController.text);
    setState(() => _units = units);
    // Re-render the same kg values in the new unit.
    _bodyweightController.text = _displayWeight(bwKg);
    _squatController.text = _displayWeight(squatKg);
    _benchController.text = _displayWeight(benchKg);
    _deadliftController.text = _displayWeight(deadKg);
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1940, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = _auth.currentUid;
    if (uid == null) {
      setState(() => _error = 'You are not signed in. Sign in and try again.');
      return;
    }
    final bodyweightKg = _parseDisplayWeight(_bodyweightController.text);
    if (bodyweightKg == null || bodyweightKg <= 0) {
      setState(() => _error = 'Enter a bodyweight greater than 0.');
      return;
    }
    final lifts = <String, double>{
      'squat': _parseDisplayWeight(_squatController.text) ?? 0,
      'bench': _parseDisplayWeight(_benchController.text) ?? 0,
      'deadlift': _parseDisplayWeight(_deadliftController.text) ?? 0,
    };
    double? weightClassKg;
    if (_weightClassLabel != null) {
      weightClassKg = _weightClassLabel == '120+'
          ? 120.0
          : double.tryParse(_weightClassLabel!);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // At least one role must stay on — if both boxes are unchecked,
    // the user still trains.
    final trains = _trains || !_coaches;
    final coaches = _coaches;
    try {
      // Save from the loaded profile, not a fresh one (A8): a brand-new
      // UserProfile(...) dropped everything the form does not own —
      // rest timers, write-back, rest alerts — resetting them to
      // defaults on every edit. copyWith keeps those fields exactly
      // as they were. First setup has no _existing, so it builds fresh
      // (defaults are correct there). saveProfile also merges, so a
      // second save racing this one cannot clobber it (A9).
      final profile = _existing?.copyWith(
            displayName: _nameController.text.trim(),
            sex: _sex,
            dob: _dob,
            country: _countryController.text.trim(),
            homeGym: _gymController.text.trim(),
            units: _units,
            barWeightKg: _barWeightKg,
            plateSet: _plateSet,
            bodyweightKg: bodyweightKg,
            weightClassKg: weightClassKg,
            mainLifts: lifts,
            trains: trains,
            coaches: coaches,
          ) ??
          UserProfile(
            uid: uid,
            displayName: _nameController.text.trim(),
            sex: _sex,
            dob: _dob,
            country: _countryController.text.trim(),
            homeGym: _gymController.text.trim(),
            units: _units,
            barWeightKg: _barWeightKg,
            plateSet: _plateSet,
            bodyweightKg: bodyweightKg,
            weightClassKg: weightClassKg,
            mainLifts: lifts,
            trains: trains,
            coaches: coaches,
          );
      await _firestore.saveProfile(profile);
      await SideService.set(
        trains ? SideService.training : SideService.coach,
      );
      if (!mounted) return;
      // The AuthGate profile stream swaps to the app shell once the
      // save lands. Only pop when this screen was pushed on top of
      // something (e.g. editing a profile from inside the app).
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not save your profile. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _countryController.dispose();
    _gymController.dispose();
    _bodyweightController.dispose();
    _squatController.dispose();
    _benchController.dispose();
    _deadliftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Set up your profile' : 'Your profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _ProfileSectionHeader('How will you use Forge?'),
                    const SizedBox(height: 4),
                    const Text(
                      'Tick one or both. The app opens on your training side when you train; switch sides anytime from the small pill at the top of the screen.',
                      style: ForgeTheme.bodyMuted,
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      title: const Text('I train'),
                      subtitle: const Text('Log my own workouts.'),
                      value: _trains,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) =>
                          setState(() => _trains = value ?? true),
                    ),
                    CheckboxListTile(
                      title: const Text('I coach'),
                      subtitle: const Text(
                        'Send programs and review my clients.',
                      ),
                      value: _coaches,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) =>
                          setState(() => _coaches = value ?? false),
                    ),
                    const SizedBox(height: 16),
                    const _ProfileSectionHeader('About you'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        hintText: 'e.g. Alex',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    const Text('Sex',
                        style: ForgeTheme.bodyMuted),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'male', label: Text('Male')),
                        ButtonSegment(value: 'female', label: Text('Female')),
                      ],
                      selected: {_sex},
                      onSelectionChanged: (s) =>
                          setState(() => _sex = s.first),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickDob,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date of birth',
                          prefixIcon: Icon(Icons.cake_outlined),
                        ),
                        child: Text(
                          _dob == null
                              ? 'Tap to pick your date of birth'
                              : DateFormat.yMMMd().format(_dob!),
                          style: TextStyle(
                            color: _dob == null
                                ? ForgeTheme.muted
                                : ForgeTheme.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        hintText: 'e.g. Canada',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _gymController,
                      decoration: const InputDecoration(
                        labelText: 'Home gym',
                        hintText: 'e.g. Buzzfit Ahuntsic',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bodyweightController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Bodyweight ($_units)',
                        hintText: _units == 'lb' ? 'e.g. 183' : 'e.g. 83',
                      ),
                      validator: (v) {
                        final kg = _parseDisplayWeight(v ?? '');
                        if (kg == null || kg <= 0) {
                          return 'Enter a bodyweight greater than 0.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _weightClassLabel,
                      decoration: const InputDecoration(
                        labelText: 'Weight class',
                      ),
                      items: _weightClasses
                          .map((c) => DropdownMenuItem(
                                value: c,
                                // Weight classes are kg classes, shown
                                // in the user's units (A19): '83 kg' /
                                // '183 lb'. '120+' is 120 kg and over.
                                child: Text(c == '120+'
                                    ? (_units == 'lb'
                                        ? '265+ lb'
                                        : '120+ kg')
                                    : formatWeight(double.parse(c), _units)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _weightClassLabel = v),
                    ),
                    const SizedBox(height: 16),
                    const _ProfileSectionHeader('Units & equipment'),
                    const SizedBox(height: 12),
                    const Text('Units',
                        style: ForgeTheme.bodyMuted),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'kg', label: Text('Kilograms')),
                        ButtonSegment(value: 'lb', label: Text('Pounds')),
                      ],
                      selected: {_units},
                      onSelectionChanged: (s) => _onUnitsChanged(s.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('Bar weight',
                        style: ForgeTheme.bodyMuted),
                    const SizedBox(height: 8),
                    SegmentedButton<double>(
                      // Bar labels follow the units toggle (A19): the
                      // stored bar is 20/15 kg, shown as lb for lb users.
                      segments: [
                        ButtonSegment(
                            value: 20.0,
                            label:
                                Text('${formatWeight(20.0, _units)} bar')),
                        ButtonSegment(
                            value: 15.0,
                            label:
                                Text('${formatWeight(15.0, _units)} bar')),
                      ],
                      selected: {_barWeightKg},
                      onSelectionChanged: (s) =>
                          setState(() => _barWeightKg = s.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('Plate set',
                        style: ForgeTheme.bodyMuted),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'calibrated', label: Text('Calibrated kg')),
                        ButtonSegment(value: 'gym', label: Text('Gym lb')),
                      ],
                      selected: {_plateSet},
                      onSelectionChanged: (s) =>
                          setState(() => _plateSet = s.first),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const _ProfileSectionHeader('Main lifts — 1RM'),
                    const SizedBox(height: 4),
                    const Text(
                      'Your best single for each lift — used for percentages and DOTS estimates.',
                      style: ForgeTheme.bodyMuted,
                    ),
                    const SizedBox(height: 12),
                    _liftField(
                      controller: _squatController,
                      label: 'Squat 1RM ($_units)',
                    ),
                    const SizedBox(height: 12),
                    _liftField(
                      controller: _benchController,
                      label: 'Bench press 1RM ($_units)',
                    ),
                    const SizedBox(height: 12),
                    _liftField(
                      controller: _deadliftController,
                      label: 'Deadlift 1RM ($_units)',
                    ),
                    const SizedBox(height: 24),
                    if (_saving)
                      const Center(child: CircularProgressIndicator())
                    else
                      FilledButton(
                        onPressed: _save,
                        child: const Text('Save profile'),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: ForgeTheme.errorText,
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Weights are stored in kilograms. Switching units only changes how they are shown.',
                      textAlign: TextAlign.center,
                      style:
                          ForgeTheme.captionMuted,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _liftField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        final kg = _parseDisplayWeight(v);
        if (kg == null || kg <= 0) return 'Enter a weight greater than 0.';
        return null;
      },
    );
  }
}

/// Small section header for the profile form.
class _ProfileSectionHeader extends StatelessWidget {
  final String text;

  const _ProfileSectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: ForgeTheme.sectionLabel,
    );
  }
}
