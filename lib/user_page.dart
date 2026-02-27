import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Ensure you have intl in pubspec.yaml
import 'chat_page.dart';
import 'notifications_page.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF027DFD),
        elevation: 2,
        title: Text(
          _selectedIndex == 0 ? "Messages" : "Contacts",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUid)
                .collection('notifications')
                .where('isSeen', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              int unreadNotifs = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return IconButton(
                icon: Badge(
                  label: Text('$unreadNotifs'),
                  isLabelVisible: unreadNotifs > 0,
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.notifications_outlined, color: Colors.white),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsPage()),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 ? FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewConversationPage())),
        backgroundColor: Colors.white,
        child: const Icon(Icons.chat_bubble_outline, color: Color(0xFF027DFD)),
      ) : null,
      body: SafeArea(
        child: _selectedIndex == 0
            ? _buildConversationsList(currentUid!)
            : _buildContactsList(currentUid!),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: const Color(0xFF027DFD),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: "Conversations"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Contacts"),
        ],
      ),
    );
  }

  Widget _buildConversationsList(String currentUid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('participants', arrayContains: currentUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
            const Text("Start Conversation Now", style: TextStyle(color: Colors.grey, fontSize: 18)),
          ]));
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, userSnapshot) {
            if (!userSnapshot.hasData) return const SizedBox.shrink();
            var users = userSnapshot.data!.docs.where((doc) => doc.id != currentUid).toList();

            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
              itemBuilder: (context, index) => _buildUserTile(users[index], currentUid, true),
            );
          },
        );
      },
    );
  }

  Widget _buildContactsList(String currentUid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var users = snapshot.data!.docs.where((doc) => doc.id != currentUid).toList();

        return ListView.separated(
          itemCount: users.length,
          separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
          itemBuilder: (context, index) => _buildUserTile(users[index], currentUid, false),
        );
      },
    );
  }

  Widget _buildUserTile(DocumentSnapshot userDoc, String currentUid, bool isConvTab) {
    // 1. Safe data extraction to prevent "Field does not exist" error
    final userData = userDoc.data() as Map<String, dynamic>?;
    if (userData == null || !userData.containsKey('name')) return const SizedBox.shrink();

    String personName = userData['name'];
    List<String> ids = [currentUid, userDoc.id];
    ids.sort();
    String roomId = ids.join("_");

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, chatSnapshot) {
        bool hasMessages = chatSnapshot.hasData && chatSnapshot.data!.docs.isNotEmpty;
        if (isConvTab && !hasMessages) return const SizedBox.shrink();

        String lastMsg = "";
        String msgTime = "";

        if (hasMessages) {
          final msgData = chatSnapshot.data!.docs.first.data() as Map<String, dynamic>;
          lastMsg = msgData['message'] ?? "";

          // 2. Format the time to display on the right
          if (msgData['timestamp'] != null) {
            Timestamp t = msgData['timestamp'] as Timestamp;
            msgTime = DateFormat('HH:mm').format(t.toDate());
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUid)
              .collection('notifications')
              .where('from', isEqualTo: userDoc.id)
              .snapshots(),
          builder: (context, notifSnapshot) {
            int unreadCount = notifSnapshot.hasData ? notifSnapshot.data!.docs.length : 0;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isConvTab ? const Color(0xFF027DFD) : Colors.teal,
                child: Text(personName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              // 3. Updated title to include person name
              title: Text(personName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: isConvTab ? Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
              // 4. Added time and badge on the right side
              trailing: isConvTab ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(msgTime, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 5),
                  if (unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: Text("$unreadCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ) : null,
              onTap: () {
                if (notifSnapshot.hasData) {
                  for (var doc in notifSnapshot.data!.docs) {
                    doc.reference.delete();
                  }
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(receiverId: userDoc.id, receiverName: personName)));
              },
            );
          },
        );
      },
    );
  }
}

class NewConversationPage extends StatefulWidget {
  const NewConversationPage({super.key});
  @override
  State<NewConversationPage> createState() => _NewConversationPageState();
}

class _NewConversationPageState extends State<NewConversationPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New conversation", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF027DFD),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              decoration: InputDecoration(
                labelText: "Recipient",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var users = snapshot.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>?;
                  if (d == null || !d.containsKey('name')) return false;
                  String name = d['name'].toString().toLowerCase();
                  return name.contains(_searchQuery) && doc.id != FirebaseAuth.instance.currentUser?.uid;
                }).toList();

                if (users.isEmpty) return const Center(child: Text("No users found"));

                return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
                  itemBuilder: (ctx, i) {
                    final d = users[i].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal,
                        child: Text(d['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(d['name']),
                      onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => ChatPage(receiverId: users[i].id, receiverName: d['name']))
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}