import 'app/bootstrap.dart';
import 'core/config/app_environment.dart';

void main() {
  bootstrap(AppEnvironment.fromCompileTime());
}
