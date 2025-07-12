import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final fullNameController = TextEditingController();
  final dobController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLogin = true;
  String? error;

  Future<void> handleAuth() async {
  if (!_formKey.currentState!.validate()) return;

  try {
    if (isLogin) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } else {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'fullName': fullNameController.text.trim(),
        'dob': dobController.text.trim(),
        'email': emailController.text.trim(),
      });
    }

    // 🔁 After successful login/registration
    // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacementNamed('/topics');
    } catch (e) {
      setState(() => error = e.toString());
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "Login" : "Register")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (error != null)
                Text(error!, style: TextStyle(color: Colors.red)),

              if (!isLogin) ...[
                TextFormField(
                  controller: fullNameController,
                  decoration: InputDecoration(labelText: "Full Name"),
                  validator: (value) => value!.isEmpty ? 'Enter your name' : null,
                ),
                TextFormField(
                  controller: dobController,
                  decoration: InputDecoration(labelText: "Date of Birth"),
                  readOnly: true,
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2000),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      dobController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                    }
                  },
                  validator: (value) => value!.isEmpty ? 'Enter your date of birth' : null,
                ),
              ],

              TextFormField(
                controller: emailController,
                decoration: InputDecoration(labelText: "Email"),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value != null && !value.contains('@') ? 'Enter valid email' : null,
              ),
              TextFormField(
                controller: passwordController,
                decoration: InputDecoration(labelText: "Password"),
                obscureText: true,
                validator: (value) =>
                    value == null || value.length < 6 ? 'Password too short' : null,
              ),

              if (!isLogin)
                TextFormField(
                  controller: confirmPasswordController,
                  decoration: InputDecoration(labelText: "Confirm Password"),
                  obscureText: true,
                  validator: (value) =>
                      value != passwordController.text ? 'Passwords do not match' : null,
                ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: handleAuth,
                child: Text(isLogin ? "Login" : "Register"),
              ),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(isLogin
                    ? "Don't have an account? Register"
                    : "Already have an account? Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
