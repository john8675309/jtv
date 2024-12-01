import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xtream_code_client/xtream_code_client.dart';
import 'package:jtv/screens/PickerScreen.dart';

class UrlInfo {
  final String baseUrl;
  final String port;

  UrlInfo(this.baseUrl, this.port);
}

class SignInScreen extends StatefulWidget {
  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController urlController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  String statusMessage = '';

  @override
  void initState() {
    super.initState();
    _autoSignIn();
  }

  UrlInfo _parseUrl(String fullUrl) {
    try {
      final uri = Uri.parse(fullUrl);
      final baseUrl = '${uri.scheme}://${uri.host}';
      final port = uri.port.toString();
      return UrlInfo(baseUrl, port);
    } catch (e) {
      print('URL parsing error: $e');
      return UrlInfo('', '');
    }
  }

  Future<void> _autoSignIn() async {
    setState(() {
      isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('url');
      final savedUsername = prefs.getString('username');
      final savedPassword = prefs.getString('password');

      if (savedUrl != null && savedUsername != null && savedPassword != null) {
        final urlInfo = _parseUrl(savedUrl);
        if (urlInfo.baseUrl.isNotEmpty && urlInfo.port.isNotEmpty) {
          await XtreamCode.initialize(
            url: urlInfo.baseUrl,
            port: urlInfo.port,
            username: savedUsername,
            password: savedPassword,
          );
          final client = XtreamCode.instance.client;

          var serverInfo = await client.serverInformation();
          if (serverInfo.userInfo.auth != null &&
              serverInfo.userInfo.auth == true) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => PickerScreen(client: client),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Auto sign-in failed: $e');
      setState(() {
        statusMessage = 'Auto sign-in failed. Please sign in manually.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> authenticate() async {
    setState(() {
      isLoading = true;
      statusMessage = '';
    });

    try {
      final urlInfo = _parseUrl(urlController.text);
      if (urlInfo.baseUrl.isEmpty || urlInfo.port.isEmpty) {
        throw Exception(
            'Invalid URL format. Please use format: http://example.com:port');
      }

      await XtreamCode.initialize(
        url: urlInfo.baseUrl,
        port: urlInfo.port,
        username: usernameController.text,
        password: passwordController.text,
      );

      final client = XtreamCode.instance.client;
      var serverInfo = await client.serverInformation();

      if (serverInfo.userInfo.auth != null &&
          serverInfo.userInfo.auth == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('url', urlController.text);
        await prefs.setString('username', usernameController.text);
        await prefs.setString('password', passwordController.text);

        setState(() {
          statusMessage = 'Signed in successfully!';
        });

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PickerScreen(client: client),
          ),
        );
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Login Failed: ${e.toString()}';
        print(e);
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sign In'),
      ),
      body: Center(
        child: isLoading
            ? CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: urlController,
                      decoration: InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'http://example.com:80',
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(labelText: 'Username'),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: authenticate,
                      child: Text('Sign In'),
                    ),
                    SizedBox(height: 20),
                    Text(
                      statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
