import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location;
import 'package:uber_clone_flutter/src/api/environment.dart';
import 'package:uber_clone_flutter/src/models/order.dart';
import 'package:uber_clone_flutter/src/models/response_api.dart';
import 'package:uber_clone_flutter/src/models/user.dart';
import 'package:uber_clone_flutter/src/provider/orders_provider.dart';
import 'package:uber_clone_flutter/src/utils/my_colors.dart';
import 'package:uber_clone_flutter/src/utils/my_snackbar.dart';
import 'package:uber_clone_flutter/src/utils/shared_pref.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class DeliveryOrderMapController {
  BuildContext context;
  Function refresh;
  Position _position;
  StreamSubscription _positionStream;

  String addressName;
  LatLng addressLatLng;

  CameraPosition initialPosition =
      CameraPosition(target: LatLng(-33.1829129, -70.8156208), zoom: 14);

  Completer<GoogleMapController> _mapController = Completer();

  BitmapDescriptor deliveryMarker;
  BitmapDescriptor homeMarker;
  Map<MarkerId, Marker> markers = <MarkerId, Marker>{};

  Order order;

  Set<Polyline> polylines = {};
  List<LatLng> points = [];

  OrdersProvider _ordersProvider = new OrdersProvider();
  User user;
  SharedPref _sharedPref = new SharedPref();

  double _distanceBetween;

  IO.Socket socket;

  Future init(BuildContext context, Function refresh) async {
    this.context = context;
    this.refresh = refresh;
    order = Order.fromJson(
        ModalRoute.of(context).settings.arguments as Map<String, dynamic>);
    deliveryMarker = await createMarkerFromAssets('assets/img/delivery2.png');
    homeMarker = await createMarkerFromAssets('assets/img/home.png');

    socket = IO.io(
        'http://${Environment.API_DELIVERY}/orders/delivery', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false
    });
    socket.connect();

    user = User.fromJson(await _sharedPref.read('user'));
    _ordersProvider.init(context, user);
    print('Orden: ${order.toJson()}');
    checkGPS();
  }

  void saveLocation() async {
    order.lat = _position.latitude;
    order.lng = _position.longitude;
    await _ordersProvider.updateLatLng(order);
  }

  void emitPosition() {
    socket.emit('position', {
      'id_order': order.id,
      'lat': _position.latitude,
      'lng': _position.longitude,
    });
  }

  void isCloseToDeliveryPosition() {
    _distanceBetween = Geolocator.distanceBetween(_position.latitude,
        _position.longitude, order.address.lat, order.address.lng);

    print('------ DISTANCIA ${_distanceBetween} ------');
  }

  void launchWaze() async {
    var url =
        'waze://?ll=${order.address.lat.toString()},${order.address.lng.toString()}';
    var fallbackUrl =
        'https://waze.com/ul?ll=${order.address.lat.toString()},${order.address.lng.toString()}&navigate=yes';
    try {
      bool launched =
          await launch(url, forceSafariVC: false, forceWebView: false);
      if (!launched) {
        await launch(fallbackUrl, forceSafariVC: false, forceWebView: false);
      }
    } catch (e) {
      await launch(fallbackUrl, forceSafariVC: false, forceWebView: false);
    }
  }

  void launchGoogleMaps() async {
    var url =
        'google.navigation:q=${order.address.lat.toString()},${order.address.lng.toString()}';
    var fallbackUrl =
        'https://www.google.com/maps/search/?api=1&query=${order.address.lat.toString()},${order.address.lng.toString()}';
    try {
      bool launched =
          await launch(url, forceSafariVC: false, forceWebView: false);
      if (!launched) {
        await launch(fallbackUrl, forceSafariVC: false, forceWebView: false);
      }
    } catch (e) {
      await launch(fallbackUrl, forceSafariVC: false, forceWebView: false);
    }
  }

  void updateToDelivered() async {
    if (_distanceBetween <= 200) {
      ResponseApi responseApi = await _ordersProvider.updateToDelivered(order);
      if (responseApi.success) {
        Fluttertoast.showToast(
            msg: responseApi.message, toastLength: Toast.LENGTH_LONG);
        Navigator.pushNamedAndRemoveUntil(
            context, 'delivery/orders/list', (route) => false);
      }
    } else {
      MySnackbar.show(
          context, 'Debes estar más cerca a la posición de entrega');
    }
  }

  Future<void> setPolylines(LatLng from, LatLng to) async {
    PointLatLng pointFrom = PointLatLng(from.latitude, from.longitude);
    PointLatLng pointTo = PointLatLng(to.latitude, to.longitude);
    PolylineResult result = await PolylinePoints().getRouteBetweenCoordinates(
        Environment.API_KEY_MAPS, pointFrom, pointTo);
    for (PointLatLng point in result.points) {
      points.add(LatLng(point.latitude, point.longitude));
    }

    Polyline polyline = Polyline(
        polylineId: PolylineId('poly'),
        color: MyColors.primaryColor,
        points: points,
        width: 6);
    polylines.add(polyline);
    refresh();
  }

  void addMarker(String markerId, double lat, double lng, String title,
      String content, BitmapDescriptor iconMarker) {
    MarkerId id = MarkerId(markerId);
    Marker marker = Marker(
        markerId: id,
        icon: iconMarker,
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: title, snippet: content));

    markers[id] = marker;

    refresh();
  }

  void selectRefPoint() {
    Map<String, dynamic> data = {
      'address': addressName,
      'lat': addressLatLng.latitude,
      'lng': addressLatLng.longitude
    };
    Navigator.pop(context, data);
  }

  Future<BitmapDescriptor> createMarkerFromAssets(String path) async {
    ImageConfiguration configuration = ImageConfiguration();
    BitmapDescriptor descriptor =
        await BitmapDescriptor.fromAssetImage(configuration, path);
    return descriptor;
  }

  Future<Null> setLocationDraggableInfo() async {
    if (initialPosition != null) {
      double lat = initialPosition.target.latitude;
      double lng = initialPosition.target.longitude;

      List<Placemark> address = await placemarkFromCoordinates(lat, lng);

      if (address != null) {
        if (address.length > 0) {
          String direction = address[0].thoroughfare;
          String street = address[0].subThoroughfare;
          String city = address[0].locality;
          String departament = address[0].administrativeArea;
          String country = address[0].country;
          addressName = '$direction #$street, $city, $departament';
          addressLatLng = new LatLng(lat, lng);
          //print('Lat: ${addressLatLng.latitude}');
          //print('Lng: ${addressLatLng.longitude}');
          refresh();
        }
      }
    }
  }

  void onMapCreated(GoogleMapController controller) {
    controller.setMapStyle(
        '[{"elementType":"geometry","stylers":[{"color":"#ebe3cd"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#523735"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#f5f1e6"}]},{"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#c9b2a6"}]},{"featureType":"administrative.land_parcel","elementType":"geometry.stroke","stylers":[{"color":"#dcd2be"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#ae9e90"}]},{"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#93817c"}]},{"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#a5b076"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#447530"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#f5f1e6"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#fdfcf8"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#f8c967"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#e9bc62"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#e98d58"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry.stroke","stylers":[{"color":"#db8555"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#806b63"}]},{"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"transit.line","elementType":"labels.text.fill","stylers":[{"color":"#8f7d77"}]},{"featureType":"transit.line","elementType":"labels.text.stroke","stylers":[{"color":"#ebe3cd"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#dfd2ae"}]},{"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#b9d3c2"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#92998d"}]}]');
    _mapController.complete(controller);
  }

  void dispose() {
    _positionStream?.cancel();
    socket?.disconnect();
  }

  void updateLocation() async {
    try {
      await _determinePosition(); // Obtiene la ubicación actual y solicita los permisos
      _position = await Geolocator
          .getLastKnownPosition(); // Almacenada la lat, lng en la variable _position
      saveLocation();
      animateCameraToPsition(_position.latitude, _position.longitude);
      addMarker('delivery', _position.latitude, _position.longitude,
          'Tu posición', '', deliveryMarker);

      addMarker('home', order.address.lat, order.address.lng,
          'Lugar de entrega', '', homeMarker);
      LatLng from = new LatLng(_position.latitude, _position.longitude);
      LatLng to = new LatLng(order.address.lat, order.address.lng);
      setPolylines(from, to);
      _positionStream = Geolocator.getPositionStream(
              desiredAccuracy: LocationAccuracy.best, distanceFilter: 1)
          .listen((Position position) {
        _position = position;
        emitPosition();
        addMarker('delivery', _position.latitude, _position.longitude,
            'Tu posición', '', deliveryMarker);
        animateCameraToPsition(_position.latitude, _position.longitude);
        isCloseToDeliveryPosition();
        refresh();
      });
    } catch (e) {
      print('Error $e');
    }
  }

  void call() {
    launch("tel://${order?.client?.phone}");
  }

  void checkGPS() async {
    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();

    if (isLocationEnabled) {
      updateLocation();
    } else {
      bool locationGPS = await location.Location().requestService();
      if (locationGPS) {
        updateLocation();
      }
    }
  }

  Future animateCameraToPsition(double lat, double lng) async {
    GoogleMapController controller = await _mapController.future;
    if (controller != null) {
      controller.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(lat, lng), zoom: 13, bearing: 0)));
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition();
  }
}
