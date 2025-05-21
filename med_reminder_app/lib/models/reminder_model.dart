import 'package:hive/hive.dart';

part 'reminder_model.g.dart';

@HiveType(typeId: 0)
class ReminderModel extends HiveObject {
  @HiveField(0)
  String medicineName;

  @HiveField(1)
  int hour;

  @HiveField(2)
  int minute;

  ReminderModel({
    required this.medicineName,
    required this.hour,
    required this.minute,
  });
}
