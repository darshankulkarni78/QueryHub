import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_page.dart';
import 'services/api_client.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  runApp(QueryHubApp(api: api));
}

class QueryHubApp extends StatelessWidget {
  final ApiClient api;

  const QueryHubApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(api: api),
      child: MaterialApp(
        title: 'QueryHub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blueGrey,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF5F5F7),
          visualDensity: VisualDensity.adaptivePlatformDensity,
          textTheme: ThemeData.light().textTheme.apply(
                fontFamily: 'RobotoMono',
              ),
        ),
        home: const HomePage(),
      ),
    );
  }
}


