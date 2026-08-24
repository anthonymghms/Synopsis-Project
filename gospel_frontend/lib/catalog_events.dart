import 'package:flutter/foundation.dart';

final ValueNotifier<int> catalogRevision = ValueNotifier<int>(0);

void notifyCatalogChanged() {
  catalogRevision.value += 1;
}
