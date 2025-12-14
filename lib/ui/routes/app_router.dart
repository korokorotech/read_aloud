// app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:read_aloud/ui/pages/home_page.dart';
import 'package:read_aloud/ui/pages/news_set_detail_page.dart';
import 'package:read_aloud/ui/pages/player_page.dart';
import 'package:read_aloud/ui/pages/web_view_page.dart';
import 'package:read_aloud/ui/routes/page_route_args/webview_page_route_args.dart';

/// ルート名（typed navigation しやすくする）
class RouteNames {
  static const homePage = 'HomePage';
  static const newsSetDetailPage = 'NewsSetDetailPage';
  static const webViewPage = 'WebViewPage';
  static const playerPage = 'PlayerPage';

  // モーダルをルート化する場合
  static const newsSetModal = 'NewsSetModal';
}

/// パス定義
class RoutePaths {
  static const homePage = '/';
  static const newsSetDetailPage = '/sets/:setId';
  static const webViewPage = '/sets/:setId/web';
  static const playerPage = '/sets/:setId/player';

  // モーダルをルート化する場合
  static const newSetModal = '/sets/new';
}

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter create() {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: RoutePaths.homePage,
      debugLogDiagnostics: true,
      routes: <RouteBase>[
        GoRoute(
          name: RouteNames.homePage,
          path: RoutePaths.homePage,
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

                    final setName = webArgs?.setName ?? 'セット $setId';

                    return MaterialPage(
                      child: WebViewPage(
                        setId: setId,
                        setName: setName,
                        initialUrl: initialUrl,
                        openAddMode: webArgs?.openAddMode ?? false,
                      ),
                    );
                  },
                ),
                GoRoute(
                  name: RouteNames.playerPage,
                  path: 'player',
                  pageBuilder: (context, state) {
                    final setId = state.pathParameters['setId']!;
                    final setName = state.uri.queryParameters['name'];
                    return MaterialPage(
                      child: PlayerPage(
                        setId: setId,
                        initialSetName: setName,
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

  Future<T?> pushSetDetail<T>(String setId) => pushNamed<T>(
        RouteNames.newsSetDetailPage,
        pathParameters: {'setId': setId},
      );

  void goWebView({
    required String setId,
    required String setName,
    required Uri initialUrl,
    bool openAddMode = false,
  }) {
    goNamed(
      RouteNames.webViewPage,
      pathParameters: {'setId': setId},
      extra: WebViewRouteArgs(
        setName: setName,
        initialUrl: initialUrl,
        openAddMode: openAddMode,
      ),
    );
  }

  Future<T?> pushWebView<T>({
    required String setId,
    required String setName,
    required Uri initialUrl,
    bool openAddMode = false,
  }) {
    return pushNamed<T>(
      RouteNames.webViewPage,
      pathParameters: {'setId': setId},
      extra: WebViewRouteArgs(
        setName: setName,
        initialUrl: initialUrl,
        openAddMode: openAddMode,
      ),
    );
  }

  Future<T?> pushPlayer<T>({
    required String setId,
    String? setName,
  }) {
    return pushNamed<T>(
      RouteNames.playerPage,
      pathParameters: {'setId': setId},
      queryParameters: {'name': setName ?? ""},
    );
  }
}
