import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:flutter/services.dart' show TextInputFormatter, WhitelistingTextInputFormatter, rootBundle;

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();

}

class _HomeState extends State<Home> {
  String statusText = "Server stopped";
  String btnText = "Start Server";
  HttpServer server;
  final _portController = new TextEditingController();
  final _timeController = new TextEditingController();
  var isStart = false;
  final _formKey = GlobalKey<FormState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  startStopServer(BuildContext context) {
    if(isStart == false) 
    {
      isStart = true;
      startServer(context);
      setState(() {
        statusText = "Starting server on port :8080";
        btnText = "Stop Server";
      });
    }
    else
    {
      isStart = false;
      server.close();
      setState(() {
        btnText = "Restart Server";
        statusText = "Server Stopped";
      });
    }
  }

  _displaySnackBar(BuildContext context, String outputStr) {
    final snackBar = SnackBar(content: Text(outputStr));
    _scaffoldKey.currentState.showSnackBar(snackBar);
  }

  @override
  void dispose() {
    _portController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  startServer(BuildContext context) async {

    server = await HttpServer.bind(InternetAddress.anyIPv4, int.parse(_portController.text));
    InternetAddress destAddr;

    final privKey = RSAKeyParser().parse(await loadPrivKey()) as RSAPrivateKey;
    final decrypter = Encrypter(RSA(privateKey: privKey));

    _displaySnackBar(context, "Server on: " + server.address.toString() + 
    ", Port: " + server.port.toString());
  
    setState(() {
      statusText = "Server on port: " + server.port.toString();
    });

    await for (var req in server) {
      ContentType contentType = req.headers.contentType;
      HttpResponse response = req.response;

      if (req.method == 'POST' &&
          contentType?.mimeType == 'application/json' /*1*/) {
        try {
          var timeNow = new DateTime.now().toUtc();
          String content = await utf8.decoder.bind(req).join(); /*2*/
          var contentMap = jsonDecode(content) as Map; /*3*/
          var data = jsonDecode(decrypter.decrypt64(contentMap["data"])) as Map;
          List<int> macAddr = data["macAddr"].cast<int>();
          int repeatNum = data["repeatNum"] ?? 1;
          var dataTimeNow = DateTime.parse(data["datetime"]);
          Duration difference = timeNow.difference(dataTimeNow);
          destAddr = InternetAddress(data["bcastAddr"]);
          assert(difference.inMinutes <= int.parse(_timeController.text));
          assert(data.containsKey("salt"));
          int portno = data["portNo"];

          print(data);

          RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((RawDatagramSocket udpSocket) {
            udpSocket.broadcastEnabled = true;
            List<int> data = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
            for(var i = 0; i < 16; ++i){
              data.addAll(macAddr);
            }
            for(var j = 0; j < repeatNum; ++j)
            {
              udpSocket.send(data, destAddr, portno);
            }
            udpSocket.close();
          });

        req.response
          ..statusCode = HttpStatus.ok
          ..write('Sent WOL packet');
        
        } catch (e) {
          response
            ..statusCode = HttpStatus.internalServerError
            ..write('Internal Server Error: $e.');
        }
      } else {
        response
          ..statusCode = HttpStatus.methodNotAllowed
          ..write('Unsupported request: ${req.method}.');
      }
      await response.close();
    }

  }

  Future<String> loadPrivKey() async {
    return await rootBundle.loadString('assets/wol_rsa_private.pem');
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('WOL Server App'),
      ),
      body: Container(
        padding: const EdgeInsets.all(6),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                  statusText,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                  softWrap: true,
              ),
              TextFormField(
                controller: _portController,
                enabled: (isStart)? false: true,
                decoration: new InputDecoration(
                    hintText: "Enter Server Listening Port",
                    labelText: "Listening Port",
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                    WhitelistingTextInputFormatter.digitsOnly
                ],
                validator: (value) {
                  if (value.isEmpty) {
                    return 'Please enter some text';
                  }

                  try {
                    var n = int.parse(value);
                    if(n < 0 || n > 65535){
                      return 'Value must be 0 <= n <= 65536';
                    }
                  } on FormatException {
                    return 'Invalid value';
                  }

                  return null;
                },
              ),
              TextFormField(
                controller: _timeController,
                enabled: (isStart)? false: true,
                decoration: new InputDecoration(
                    hintText: "Enter allowed time difference (in mins)",
                    labelText: "Time difference",
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                    WhitelistingTextInputFormatter.digitsOnly
                ],
                validator: (value) {
                  if (value.isEmpty) {
                    return 'Please enter some text';
                  }

                  try {
                    int.parse(value);
                  } on FormatException {
                    return 'Invalid value';
                  }

                  return null;
                },
              ),
              RaisedButton(
                onPressed: (){
                  if((_formKey.currentState.validate() && 
                  isStart == false) || (isStart == true))
                  {
                    startStopServer(context);
                  }
                },
                child: Text(btnText),
              )
            ],
          )
        )
      )
    );
  }
}