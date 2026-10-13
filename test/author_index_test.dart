import 'package:flutter_test/flutter_test.dart';

import 'author_index_checks.dart' as checks;

void main() {
  test('local author index preserves source, exact names and durable updates',
      checks.main);
}
