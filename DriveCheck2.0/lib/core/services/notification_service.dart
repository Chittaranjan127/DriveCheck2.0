import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications. Used in the demo to mimic an incoming SMS OTP.
///
/// Bootstrap once at app start with `await NotificationService.instance.init()`.
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _plugin.initialize(initSettings);

    // Explicitly request iOS permission so we get a definite yes/no.
    final iosGranted = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;

    // Android 13+ runtime permission.
    final androidGranted = await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;

    debugPrint('[notif] init done. iOS granted=$iosGranted, Android granted=$androidGranted');
    _initialized = true;
  }

  /// Fires an SMS-styled notification with the OTP.
  Future<void> showOtp(String otp) async {
    debugPrint('[notif] showOtp called: $otp (initialized=$_initialized)');
    if (!_initialized) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'otp_channel',
        'OTP Messages',
        channelDescription: 'One-time passwords from DriveCheck',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        ticker: 'OTP',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    try {
      await _plugin.show(
        _otpNotificationId,
        'MD-DRIVE',
        '$otp is your DriveCheck OTP. Do not share with anyone. Valid for 5 minutes.',
        details,
      );
      debugPrint('[notif] show() succeeded');
    } catch (e, st) {
      debugPrint('[notif] show() failed: $e\n$st');
    }
  }

  static const int _otpNotificationId = 1001;
}
