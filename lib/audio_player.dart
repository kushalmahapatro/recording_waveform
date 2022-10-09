import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_waveform.dart';

class AudioPlayer extends StatefulWidget {
  /// Path from where to play recorded audio
  final String source;

  /// Callback when audio file should be removed
  /// Setting this to null hides the delete button
  final VoidCallback onDelete;
  final Waveform waveform;
  final Duration duration;

  const AudioPlayer({
    Key? key,
    required this.source,
    required this.onDelete,
    required this.waveform,
    required this.duration,
  }) : super(key: key);

  @override
  State<AudioPlayer> createState() => AudioPlayerState();
}

class AudioPlayerState extends State<AudioPlayer> {
  // final progressStream = BehaviorSubject<WaveformProgress>();
  static const double _controlSize = 56;
  static const double _deleteBtnSize = 24;

  final _audioPlayer = ap.AudioPlayer();
  late StreamSubscription<void> _playerStateChangedSubscription;
  late StreamSubscription<Duration?> _durationChangedSubscription;
  late StreamSubscription<Duration> _positionChangedSubscription;
  Duration? _position;
  Duration? _duration;
  Waveform? extractedWaveform;
  late Stream<WaveformProgress> waveformStream;

  Future<void> _init() async {
    try {
      final waveFile =
          File(p.join((await getTemporaryDirectory()).path, 'waveform.wave'));
      waveformStream = JustWaveform.extract(
          audioInFile: File(widget.source.replaceAll('file://', '')),
          waveOutFile: waveFile);
      final progress = await waveformStream.last;
      extractedWaveform = progress.waveform;
      setState(() {});
    } catch (e) {
      print('error- $e');
    }
  }

  @override
  void initState() {
    _init();

    _playerStateChangedSubscription =
        _audioPlayer.onPlayerComplete.listen((state) async {
      await stop();
      setState(() {});
    });
    _positionChangedSubscription = _audioPlayer.onPositionChanged.listen(
      (position) => setState(() {
        _position = position;
      }),
    );
    _durationChangedSubscription = _audioPlayer.onDurationChanged.listen(
      (duration) => setState(() {
        _duration = duration;
      }),
    );

    super.initState();
  }

  @override
  void dispose() {
    _playerStateChangedSubscription.cancel();
    _positionChangedSubscription.cancel();
    _durationChangedSubscription.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print(Int16List.fromList(widget.waveform.data));
    String formatNumber(int number) {
      String numberStr = number.toString();
      if (number < 10) {
        numberStr = '0$numberStr';
      }

      return numberStr;
    }

    Widget buildTimer() {
      final String minutes = formatNumber(widget.duration.inSeconds ~/ 60);
      final String seconds = formatNumber(widget.duration.inSeconds % 60);

      return Text(
        '$minutes : $seconds',
        style: const TextStyle(color: Colors.red),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _buildControl(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSlider(constraints.maxWidth),
                    buildTimer(),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      color: Color(0xFF73748D), size: _deleteBtnSize),
                  onPressed: () {
                    stop().then((value) => widget.onDelete());
                  },
                ),
              ],
            ),
            const Text("Waveform"),
            SizedBox(
              width: 300,
              height: 50,
              child: AudioWaveformWidget(
                waveform: widget.waveform,
                start: Duration.zero,
                duration: widget.waveform.duration,
                scale: 3,
                waveColor: Theme.of(context).primaryColor,
              ),
            ),
            const Text("Extracted - Waveform"),
            if (extractedWaveform != null) ...[
              SizedBox(
                width: 300,
                height: 50,
                child: AudioWaveformWidget(
                  waveform: extractedWaveform!,
                  start: Duration.zero,
                  duration: extractedWaveform!.duration,
                  scale: 3,
                  pixelsPerStep: 8,
                  waveColor: Theme.of(context).primaryColor,
                ),
              ),
            ]
          ],
        );
      },
    );
  }

  Widget _buildControl() {
    Icon icon;
    Color color;

    if (_audioPlayer.state == ap.PlayerState.playing) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.play_arrow, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child:
              SizedBox(width: _controlSize, height: _controlSize, child: icon),
          onTap: () {
            if (_audioPlayer.state == ap.PlayerState.playing) {
              pause();
            } else {
              play();
            }
          },
        ),
      ),
    );
  }

  Widget _buildSlider(double widgetWidth) {
    bool canSetValue = false;
    final duration = _duration;
    final position = _position;

    if (duration != null && position != null) {
      canSetValue = position.inMilliseconds > 0;
      canSetValue &= position.inMilliseconds < duration.inMilliseconds;
    }

    double width = widgetWidth - _controlSize - _deleteBtnSize;
    width -= _deleteBtnSize;

    return SizedBox(
      width: width,
      child: Slider(
        activeColor: Theme.of(context).primaryColor,
        inactiveColor: Theme.of(context).primaryColor.withOpacity(0.3),
        onChanged: (v) {
          if (duration != null) {
            final position = v * duration.inMilliseconds;
            _audioPlayer.seek(Duration(milliseconds: position.round()));
          }
        },
        value: canSetValue && duration != null && position != null
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0,
      ),
    );
  }

  Future<void> play() {
    return _audioPlayer.play(
      kIsWeb ? ap.UrlSource(widget.source) : ap.DeviceFileSource(widget.source),
    );
  }

  Future<void> pause() => _audioPlayer.pause();

  Future<void> stop() => _audioPlayer.stop();
}
