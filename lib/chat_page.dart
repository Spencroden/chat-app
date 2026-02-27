import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;

  const ChatPage({super.key, required this.receiverId, required this.receiverName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final String currentId = FirebaseAuth.instance.currentUser!.uid;

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String msg = _messageController.text.trim();
    _messageController.clear();

    List<String> ids = [currentId, widget.receiverId];
    ids.sort();
    String roomId = ids.join("_");

    try {
      // 1. Fetch current user's name from Firestore for the notification
      // This ensures 'senderName' is never "Someone" or null
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentId)
          .get();

      String senderName = "Someone";
      if (userDoc.exists && userDoc.data() != null) {
        senderName = (userDoc.data() as Map<String, dynamic>)['name'] ?? "Someone";
      }

      // 2. Save individual message to the chat room
      await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').add({
        'senderId': currentId,
        'message': msg,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 3. Update the Chat Room metadata (for the Conversations list preview)
      await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set({
        'participants': ids,
        'lastTimestamp': FieldValue.serverTimestamp(),
        'lastMessage': msg,
      }, SetOptions(merge: true));

      // 4. Trigger Notification for Receiver
      // isSeen: false tracks the bell badge on UsersPage
      await FirebaseFirestore.instance.collection('users').doc(widget.receiverId).collection('notifications').add({
        'from': currentId,
        'senderName': senderName,
        'message': msg,
        'timestamp': FieldValue.serverTimestamp(),
        'isSeen': false,
      });
    } catch (e) {
      debugPrint("Error sending message: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> ids = [currentId, widget.receiverId];
    ids.sort();
    String roomId = ids.join("_");

    return Scaffold(
      backgroundColor: const Color(0xFFFDEEF4),
      appBar: AppBar(
        title: Text(widget.receiverName, style: const TextStyle(color: Color(0xFF027DFD), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chat_rooms').doc(roomId)
                  .collection('messages').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("Error loading messages"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                return ListView.builder(
                  reverse: true,
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    bool isMe = data['senderId'] == currentId;

                    Timestamp? t = data['timestamp'] as Timestamp?;
                    String time = t != null ? DateFormat('HH:mm').format(t.toDate()) : "";

                    return _buildMessageBubble(data['message'] ?? "", isMe, time);
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String msg, bool isMe, String time) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF027DFD) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: isMe ? const Radius.circular(15) : const Radius.circular(0),
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(15),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
                msg,
                style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 16)
            ),
            const SizedBox(height: 4),
            Text(
                time,
                style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w300
                )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "Type a message...",
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF027DFD),
            child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage
            ),
          ),
        ],
      ),
    );
  }
}