import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:nsd/nsd.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:get_ip_address/get_ip_address.dart';
import 'package:network_info_plus/network_info_plus.dart';

const String serviceTypeDiscover = '_http._tcp';
const String serviceTypeRegister = '_http._tcp';
const utf8encoder = Utf8Encoder();

// ตัวแปร global
late WebSocket webSocket;
late WebSocketChannel socket;
late HttpServer server;
var ipAddress = IpAddress(type: RequestType.json);
final info = NetworkInfo();
void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final discoveries = <Discovery>[];
  final registrations = <Registration>[];
  int nextPort = 8080;
  MyAppState() {
    enableLogging(LogTopic.calls);
  }

  @override
  void initState() {
    getIP();
    super.initState();
  }

  @override
  void dispose() {
    // registrations.forEach((value) {
    //   unregister(value);
    // });
    // registrations.clear();

    super.dispose();
    print("dispose =====> ${registrations.length}");
    // unregister(registration);
  }

  Future<void> getIP() async {
    final ip = await info.getWifiIP(); // Fetch Wi-Fi IP address
    print("my ip ======> ${ip}");
  }

  Future<void> addDiscovery() async {
    final discovery = await startDiscovery(serviceTypeDiscover);
    setState(() {
      discoveries.add(discovery);
    });
  }

  Future<void> dismissDiscovery(Discovery discovery) async {
    setState(() {
      /// remove fast, without confirmation, to avoid "onDismissed" error.
      discoveries.remove(discovery);
    });

    await stopDiscovery(discovery);
  }

  Future<void> addRegistration() async {
    final ip = await info.getWifiIP(); // Fetch Wi-Fi IP address
    final service = Service(
        name: 'MeriPOS,${ip.toString()}',
        type: serviceTypeRegister,
        host: ip.toString(),
        port: nextPort,
        txt: createTxt());

    final registration = await register(service);
    setState(() {
      registrations.add(registration);
    });
    final server = await HttpServer.bind(ip.toString(), 8080);

    print(
        'WebSocket Server เริ่มทำงานที่: ${server.address.address}:${server.port}');

    // รับการเชื่อมต่อ WebSocket
    await for (HttpRequest request in server) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        webSocket = await WebSocketTransformer.upgrade(request);
        print('Client เชื่อมต่อแล้ว');

        // ฟังข้อความจาก Client
        webSocket.listen((message) {
          print('ข้อความจาก Client: $message');
          // webSocket.add('Server ได้รับข้อความ: $message');
        });
      } else {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..close();
      }
    }
  }

  Future<void> dismissRegistration(Registration registration) async {
    setState(() {
      /// remove fast, without confirmation, to avoid "onDismissed" error.
      registrations.remove(registration);
    });
    await unregister(registration);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SpeedDial(
          icon: Icons.add,
          spacing: 10,
          spaceBetweenChildren: 5,
          children: [
            SpeedDialChild(
              elevation: 2,
              child: const Icon(Icons.wifi_tethering),
              label: 'Register Service',
              onTap: () async => addRegistration(),
            ),
            SpeedDialChild(
              elevation: 2,
              child: const Icon(Icons.wifi_outlined),
              label: 'Start Discovery',
              onTap: () async => addDiscovery(),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                controller: ScrollController(),
                itemBuilder: buildDiscovery,
                itemCount: discoveries.length,
              ),
            ),
            const Divider(
              height: 20,
              thickness: 4,
              indent: 0,
              endIndent: 0,
              color: Colors.blue,
            ),
            Expanded(
              child: ListView.builder(
                controller: ScrollController(),
                itemBuilder: buildRegistration,
                itemCount: registrations.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDiscovery(context, index) {
    final discovery = discoveries.elementAt(index);
    return Dismissible(
        key: ValueKey(discovery.id),
        onDismissed: (_) async => dismissDiscovery(discovery),
        child: DiscoveryWidget(discovery));
  }

  Widget buildRegistration(context, index) {
    final registration = registrations.elementAt(index);
    return Dismissible(
        key: ValueKey(registration.id),
        onDismissed: (_) async => dismissRegistration(registration),
        child: RegistrationWidget(registration));
  }
}

class DiscoveryWidget extends StatefulWidget {
  final Discovery discovery;

  DiscoveryWidget(this.discovery) : super(key: ValueKey(discovery.id));

  @override
  State createState() => DiscoveryState();
}

class DiscoveryState extends State<DiscoveryWidget> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
              leading: const Icon(Icons.wifi_outlined),
              title: Text('Discovery ${shorten(widget.discovery.id)}')),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: ChangeNotifierProvider.value(
                value: widget.discovery,
                child: Consumer<Discovery>(builder: buildDataTable),
              )),
          MaterialButton(
            onPressed: () {
              // ส่งข้อความถึง Server
              socket.sink.add('Hello from Client!');
            },
            child: Text("send msg to server"),
          ),
          const SizedBox(
            height: 16,
          ),
        ],
      ),
    );
  }

  Widget buildDataTable(
      BuildContext context, Discovery discovery, Widget? child) {
    return DataTable(
      headingRowHeight: 24,
      dataRowMinHeight: 24,
      dataRowMaxHeight: 24,
      dataTextStyle: const TextStyle(color: Colors.black, fontSize: 12),
      columnSpacing: 8,
      horizontalMargin: 0,
      headingTextStyle: const TextStyle(
          color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600),
      columns: <DataColumn>[
        buildDataColumn('Name'),
        buildDataColumn('Type'),
        buildDataColumn('Host'),
        buildDataColumn('Port'),
      ],
      rows: buildDataRows(discovery),
    );
  }

  DataColumn buildDataColumn(String name) {
    return DataColumn(
      label: Text(
        name,
      ),
    );
  }

  List<DataRow> buildDataRows(Discovery discovery) {
    return discovery.services
        .map((e) => DataRow(
              onLongPress: () {
                print(e.name?.split(",").toList()[1]);
              },
              onSelectChanged: (bool? selected) {
                final serverIp = e.name?.split(',').toList()[1];
                _showAlertDialog(context, serverIp!);
                print(e.name?.split(',').toList()[1]);
              },
              cells: <DataCell>[
                DataCell(Text(e.name ?? 'unknown')),
                DataCell(Text(e.type ?? 'unknown')),
                DataCell(Text(e.host ?? 'unknown')),
                DataCell(Text(e.port != null ? '${e.port}' : 'unknown'))
              ],
            ))
        .toList();
  }
}

class RegistrationWidget extends StatelessWidget {
  final Registration registration;

  RegistrationWidget(this.registration) : super(key: ValueKey(registration.id));

  @override
  Widget build(BuildContext context) {
    final service = registration.service;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: Text('Registration ${shorten(registration.id)}'),
            subtitle: Text(
              'Name: ${service.name} ▪️ '
              'Type: ${service.type} ▪️ '
              'Host: ${service.host} ▪️ '
              'Port: ${service.port}',
              style: const TextStyle(color: Colors.black, fontSize: 12),
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          MaterialButton(
            onPressed: () {
              // ส่งข้อความถึง Server
              webSocket.add('Server send msg to client');
            },
            child: Text("send msg to client"),
          ),
        ],
      ),
    );
  }
}

/// Shortens the id for display on-screen.
String shorten(String? id) {
  return id?.toString().substring(0, 4) ?? 'unknown';
}

/// Creates a txt attribute object that showcases the most common use cases.
Map<String, Uint8List?> createTxt() {
  return <String, Uint8List?>{
    'a-string': utf8encoder.convert('κόσμε'),
    'a-blank': Uint8List(0),
    'a-null': null,
  };
}

void _showAlertDialog(BuildContext context, String serverIp) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text("Confirmation"),
        content: Text("Are you sure you want to proceed?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
              print("Cancel pressed");
            },
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
// กำหนดค่าให้ตัวแปร global
              // socket2 = await Socket.connect(serverIp, 8080);

              socket = WebSocketChannel.connect(
                Uri.parse('ws://${serverIp}:8080'), // แทนที่ด้วย IP ของ Server
              );

              // รับข้อความจาก Server
              socket.stream.listen((message) {
                print('ข้อความจาก Server: $message');
              });

              // ปิดการเชื่อมต่อหลังใช้งาน
              // Future.delayed(Duration(seconds: 10), () {
              //   socket.sink.close();
              // });

              Navigator.of(context).pop(); // Close the dialog
              print("OK pressed");
            },
            child: Text("OK"),
          ),
        ],
      );
    },
  );
}
