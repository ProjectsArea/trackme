import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, dynamic>> _userCache = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _getUser(String userId) async {
    if (_userCache.containsKey(userId)) return _userCache[userId];
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = snap.data();
      if (data != null) {
        _userCache[userId] = data;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF1E40AF);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('All Feedback', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search by employee, title, comments...',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('visit_feedback')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                final query = _searchController.text.trim().toLowerCase();

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final userId = (data['userId'] ?? '') as String;
                    final title = (data['title'] ?? '') as String;
                    final comments = (data['comments'] ?? '') as String;
                    final rating = (data['rating'] ?? 0) as int;
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                    // Client-side search filtering
                    final inText = (
                      title.toLowerCase().contains(query) ||
                      comments.toLowerCase().contains(query)
                    );

                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _getUser(userId),
                      builder: (context, userSnap) {
                        final employeeName = (userSnap.data?['employeeName'] ?? 'Unknown') as String;
                        final department = (userSnap.data?['department'] ?? '-') as String;
                        final matchName = employeeName.toLowerCase().contains(query);
                        if (query.isNotEmpty && !(inText || matchName)) {
                          return const SizedBox.shrink();
                        }

                        return _feedbackCard(
                          primary: primary,
                          employeeName: employeeName,
                          department: department,
                          title: title,
                          comments: comments,
                          rating: rating,
                          createdAt: createdAt,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackCard({
    required Color primary,
    required String employeeName,
    required String department,
    required String title,
    required String comments,
    required int rating,
    required DateTime? createdAt,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 6))],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.person, color:Color(30)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              employeeName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1F2937)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                            child: Text(department, style: const TextStyle(color: Colors.blue, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(title.isEmpty ? 'Untitled' : title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(comments, style: TextStyle(color: Colors.grey.shade700, height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                Row(children: [
                  for (int i = 1; i <= 5; i++)
                    Icon(i <= rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 18),
                ]),
                const Spacer(),
                const Icon(Icons.schedule, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text(
                  createdAt != null ? _timeAgo(createdAt) : '-',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}


