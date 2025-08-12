import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AdminTripDetailScreen extends StatelessWidget {
  final String sessionId;
  const AdminTripDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E40AF),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('navigation_sessions').doc(sessionId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() ?? {};
          final origin = (data['origin'] ?? {}) as Map<String, dynamic>;
          final destination = (data['destination'] ?? {}) as Map<String, dynamic>;
          final lastLocation = (data['lastLocation'] ?? {}) as Map<String, dynamic>;
          final purpose = (data['purpose'] ?? '') as String;
          final status = (data['status'] ?? 'active') as String;
          final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
          final endedAt = (data['endedAt'] as Timestamp?)?.toDate();

          final originLatLng = (origin['lat'] != null && origin['lng'] != null)
              ? LatLng((origin['lat'] as num).toDouble(), (origin['lng'] as num).toDouble())
              : const LatLng(20.5937, 78.9629);
          final destLatLng = (destination['lat'] != null && destination['lng'] != null)
              ? LatLng((destination['lat'] as num).toDouble(), (destination['lng'] as num).toDouble())
              : const LatLng(20.5937, 78.9629);
          final lastLatLng = (lastLocation['lat'] != null && lastLocation['lng'] != null)
              ? LatLng((lastLocation['lat'] as num).toDouble(), (lastLocation['lng'] as num).toDouble())
              : null;

          final bounds = LatLngBounds(
            southwest: LatLng(
              (originLatLng.latitude <= destLatLng.latitude ? originLatLng.latitude : destLatLng.latitude),
              (originLatLng.longitude <= destLatLng.longitude ? originLatLng.longitude : destLatLng.longitude),
            ),
            northeast: LatLng(
              (originLatLng.latitude >= destLatLng.latitude ? originLatLng.latitude : destLatLng.latitude),
              (originLatLng.longitude >= destLatLng.longitude ? originLatLng.longitude : destLatLng.longitude),
            ),
          );

          final markers = <Marker>{
            Marker(
              markerId: const MarkerId('origin'),
              position: originLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(title: origin['address']?.toString() ?? 'Origin'),
            ),
            Marker(
              markerId: const MarkerId('dest'),
              position: destLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(title: destination['address']?.toString() ?? 'Destination'),
            ),
          };
          if (lastLatLng != null) {
            markers.add(
              Marker(
                markerId: const MarkerId('last'),
                position: lastLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                infoWindow: const InfoWindow(title: 'Last known location'),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map preview
                SizedBox(
                  height: 260,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: originLatLng, zoom: 12),
                    markers: markers,
                    onMapCreated: (c) {
                      c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (status == 'active' ? Colors.green : Colors.grey).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: status == 'active' ? Colors.green : Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (purpose.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                purpose,
                                style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _infoTile('From', origin['address']?.toString() ?? '-', Icons.flag_circle, Colors.green),
                      const SizedBox(height: 8),
                      _infoTile('To', destination['address']?.toString() ?? '-', Icons.place, Colors.red),
                      const SizedBox(height: 8),
                      _infoTile(
                        'Last location',
                        lastLatLng != null
                            ? '${(lastLatLng.latitude).toStringAsFixed(6)}, ${(lastLatLng.longitude).toStringAsFixed(6)}'
                            : '-',
                        Icons.my_location,
                        Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: Colors.blueGrey),
                          const SizedBox(width: 6),
                          Text(
                            startedAt != null ? startedAt.toString() : '-',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                        ],
                      ),
                      if (endedAt != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.stop_circle_outlined, size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            Text(
                              endedAt.toString(),
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoTile(String label, String value, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}


