import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../main.dart';
import '../models/reminder_model.dart'; // Make sure this is your Hive model
import 'package:hive/hive.dart';

class MedicineReminderScreen extends StatefulWidget {
  const MedicineReminderScreen({super.key});

  @override
  State<MedicineReminderScreen> createState() => _MedicineReminderScreenState();
}

class _MedicineReminderScreenState extends State<MedicineReminderScreen> {
  final TextEditingController _medicineController = TextEditingController();
  TimeOfDay? _selectedTime;
  List<ReminderModel> reminders = [];
  final reminderBox = Hive.box<ReminderModel>('reminders');

  @override
  void initState() {
    super.initState();
    reminders = reminderBox.values.toList();
  }

  Future<void> _scheduleReminder(String medicineName, TimeOfDay time) async {
    final now = DateTime.now();
    final scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Medicine Reminder',
      'It\'s time to take: $medicineName',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'med_reminder_channel',
          'Medicine Reminder Channel',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _addReminder() {
    if (_medicineController.text.isNotEmpty && _selectedTime != null) {
      final medicine = _medicineController.text;
      final time = _selectedTime!;

      final reminder = ReminderModel(
        medicineName: medicine,
        hour: time.hour,
        minute: time.minute,
      );

      reminderBox.add(reminder);

      setState(() {
        reminders = reminderBox.values.toList();
      });

      _scheduleReminder(medicine, time);

      _medicineController.clear();
      _selectedTime = null;
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  @override
  void dispose() {
    _medicineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medicine Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _medicineController,
              decoration: const InputDecoration(labelText: 'Medicine Name'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.access_time),
              label: Text(_selectedTime == null
                  ? 'Pick Time'
                  : _selectedTime!.format(context)),
              onPressed: _pickTime,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addReminder,
              child: const Text('Add Reminder'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scheduled Reminders:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: reminders.length,
                itemBuilder: (context, index) {
                  final reminder = reminders[index];
                  final time = TimeOfDay(
                      hour: reminder.hour, minute: reminder.minute);
                  final key = reminderBox.keyAt(index);

                  return ListTile(
                    title: Text(
                        '${reminder.medicineName} at ${time.format(context)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () {
                            _medicineController.text = reminder.medicineName;
                            _selectedTime = time;

                            reminderBox.delete(key);
                            setState(() {
                              reminders = reminderBox.values.toList();
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            reminderBox.delete(key);
                            setState(() {
                              reminders = reminderBox.values.toList();
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
