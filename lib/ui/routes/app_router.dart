// app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:read_aloud/ui/pages/home_page.dart';
import 'package:read_aloud/ui/pages/news_set_detail_page.dart';
import 'package:read_aloud/ui/pages/web_view_page.dart';

/// ルート名（typed navigation しやすくする）
class RouteNames {
  static const homePage = 'HomePage';
  static const newsSetDetailPage = 'NewsSetDetailPage';
  static const webViewPage = 'WebViewPage';

  // モーダルをルート化する場合
  static const newsSetModal = 'NewsSetModal';
}

/// パス定義
class RoutePaths {
  static const home = '/';
  static const setDetail = '/sets/:setId';
  static const webView = '/sets/:setId/web';

  // モーダルをルート化する場合
  static const newSetModal = '/sets/new';
}

/// WebView に渡す引数（開始URLなど）
/// - 「検索して追加」「ニュースから追加」「その他URL」いずれも initialUrl で統一
@immutable
class WebViewRouteArgs {
  const WebViewRouteArgs({
    required this.initialUrl,
    this.openAddMode = false,
  });

  final Uri initialUrl;

  /// 例えば「到達時は追加モードONにしたい」等があれば使う
  final bool openAddMode;
}

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();
  static final shellNavigatorKey =
      GlobalKey<NavigatorState>(); // 将来ShellRoute化するなら

  /// GoRouter 本体
  static GoRouter create() {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: RoutePaths.home,
      debugLogDiagnostics: true,
      routes: <RouteBase>[
        GoRoute(
          name: RouteNames.homePage,
          path: RoutePaths.home,
          pageBuilder: (context, state) => const MaterialPage(
            child: HomePage(),
          ),
          routes: [
            GoRoute(
              name: RouteNames.newsSetDetailPage,
              path: 'sets/:setId', // ← home配下の相対パスでもOK
              pageBuilder: (context, state) {
                final setId = state.pathParameters['setId']!;
                return MaterialPage(
                  child: NewsSetDetailPage(setId: setId),
                );
              },
              routes: [
                GoRoute(
                  name: RouteNames.webViewPage,
                  path: 'web',
                  pageBuilder: (context, state) {
                    final setId = state.pathParameters['setId']!;
                    final args = state.extra;

                    // extra で開始URLを受け取る想定（推奨）
                    final WebViewRouteArgs? webArgs =
                        args is WebViewRouteArgs ? args : null;

                    // フォールバック：query で渡す場合（任意）
                    final qpUrl = state.uri.queryParameters['url'];
                    final fallbackUrl =
                        qpUrl != null ? Uri.tryParse(qpUrl) : null;

                    final initialUrl = webArgs?.initialUrl ?? fallbackUrl;
                    if (initialUrl == null) {
                      // ここに来るのは想定外。とりあえず home に返すなど。
                      return const MaterialPage(child: HomePage());
                    }

                    return MaterialPage(
                      child: WebViewPage(
                        setId: setId,
                        initialUrl: initialUrl,
                        openAddMode: webArgs?.openAddMode ?? false,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
      errorPageBuilder: (context, state) {
        return MaterialPage(
          child: Scaffold(
            appBar: AppBar(title: const Text('Not Found')),
            body: Center(
              child: Text('Route not found: ${state.uri}'),
            ),
          ),
        );
      },
    );
  }
}

/// 画面側から呼びやすい helper（任意）
extension AppRouteNav on BuildContext {
  void goHome() => goNamed(RouteNames.homePage);

  void goSetDetail(String setId) =>
      goNamed(RouteNames.newsSetDetailPage, pathParameters: {'setId': setId});

  void goWebView({
    required String setId,
    required Uri initialUrl,
    bool openAddMode = false,
  }) {
    goNamed(
      RouteNames.webViewPage,
      pathParameters: {'setId': setId},
      extra: WebViewRouteArgs(
        initialUrl: initialUrl,
        openAddMode: openAddMode,
      ),
    );
  }
}
