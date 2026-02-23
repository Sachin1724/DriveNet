import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator, TextInput } from 'react-native';
import * as WebBrowser from 'expo-web-browser';
import * as Google from 'expo-auth-session/providers/google';
import { makeRedirectUri } from 'expo-auth-session';
import AsyncStorage from '@react-native-async-storage/async-storage';
import axios from 'axios';
import { API, GOOGLE_CLIENT_ID, GOOGLE_ANDROID_CLIENT_ID } from '../config';

WebBrowser.maybeCompleteAuthSession();

export default function LoginScreen({ navigation }: any) {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');

    const [request, response, promptAsync] = Google.useAuthRequest({
        androidClientId: GOOGLE_ANDROID_CLIENT_ID,
        iosClientId: GOOGLE_CLIENT_ID,
        webClientId: GOOGLE_CLIENT_ID,
        redirectUri: makeRedirectUri({
            scheme: 'drivenet'
        }),
    });

    useEffect(() => {
        checkExistingToken();
    }, []);

    useEffect(() => {
        if (response?.type === 'success') {
            const { authentication } = response;
            if (authentication?.idToken || authentication?.accessToken) {
                handleServerAuth(authentication.idToken || authentication.accessToken);
            }
        } else if (response?.type === 'error') {
            setError('Google Authentication Failed');
        }
    }, [response]);

    const checkExistingToken = async () => {
        const token = await AsyncStorage.getItem('drivenet_token');
        if (token) {
            navigation.replace('Dashboard');
        }
    };

    const handleServerAuth = async (google_token: string) => {
        setLoading(true);
        setError('');
        try {
            const res = await axios.post(`${API}/api/auth/login`, { google_token });
            if (res.data.token) {
                await AsyncStorage.setItem('drivenet_token', res.data.token);
                await AsyncStorage.setItem('drivenet_user', JSON.stringify(res.data.user));
                navigation.replace('Dashboard');
            }
        } catch (err: any) {
            setError(err.response?.data?.error || 'Login failed. Check your connection and try again.');
            setLoading(false);
        }
    };

    return (
        <View style={styles.container}>
            <View style={styles.content}>
                <View style={styles.scanline} pointerEvents="none" />
                <View style={styles.header}>
                    <Text style={styles.icon}>🛡️</Text>
                    <Text style={styles.title}>Drive<Text style={styles.titleAccent}>Net</Text></Text>
                </View>

                <View style={styles.box}>
                    <Text style={styles.boxTitle}>AUTHORIZED TERMINAL</Text>
                    <Text style={styles.boxSubtitle}>Secure Cloud Proxy Node</Text>

                    {error ? <Text style={styles.errorText}>{error}</Text> : null}

                    <TouchableOpacity
                        style={styles.btn}
                        disabled={!request || loading}
                        onPress={() => promptAsync()}
                    >
                        {loading ? (
                            <ActivityIndicator color="#fff" />
                        ) : (
                            <Text style={styles.btnText}>VERIFY GOOGLE CREDENTIALS</Text>
                        )}
                    </TouchableOpacity>

                </View>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0e0e0e',
        justifyContent: 'center',
        padding: 24,
    },
    content: {
        maxWidth: 400,
        width: '100%',
        alignSelf: 'center',
    },
    scanline: {
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'rgba(255, 70, 85, 0.05)',
        zIndex: -1,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 40,
    },
    icon: {
        fontSize: 24,
        marginRight: 8,
    },
    title: {
        fontSize: 28,
        fontWeight: '900',
        color: '#fff',
        letterSpacing: 4,
    },
    titleAccent: {
        color: '#ff4655',
    },
    box: {
        backgroundColor: '#141414',
        borderWidth: 1,
        borderColor: '#222',
        padding: 32,
        alignItems: 'center',
    },
    boxTitle: {
        color: '#fff',
        fontSize: 16,
        fontWeight: '800',
        letterSpacing: 2,
        marginBottom: 8,
    },
    boxSubtitle: {
        color: '#64748b',
        fontSize: 12,
        fontWeight: '500',
        letterSpacing: 1,
        marginBottom: 24,
    },
    errorText: {
        color: '#ef4444',
        fontSize: 12,
        backgroundColor: 'rgba(239, 68, 68, 0.1)',
        padding: 12,
        marginBottom: 24,
        textAlign: 'center',
        width: '100%',
    },
    btn: {
        backgroundColor: '#ff4655',
        paddingVertical: 14,
        paddingHorizontal: 24,
        width: '100%',
        alignItems: 'center',
        borderLeftWidth: 4,
        borderLeftColor: '#fff',
    },
    btnText: {
        color: '#fff',
        fontSize: 12,
        fontWeight: 'bold',
        letterSpacing: 2,
    }
});
