import 'package:uber_clone_flutter/src/models/mercado_pago_credentials.dart';

class Environment {
  static const String API_DELIVERY = "192.168.8.101:3000";
  static const String API_KEY_MAPS = "AIzaSyB1Go6vObT-26xuJf1-2y_hnt-i2ak77_k";

  static MercadoPagoCredentials mercadoPagoCredentials = MercadoPagoCredentials(
      publicKey: 'TEST-0f45fa4d-760a-424a-a0d4-eb913bfca4a0',
      accessToken:
          'TEST-8793243825979411-100915-d69ded206777f51a45a7e4d83a198c6b-122925330');
}
