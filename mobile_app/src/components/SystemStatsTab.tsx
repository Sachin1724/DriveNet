import React, { useState, useEffect, useRef } from 'react';
import { View, Text, StyleSheet, ScrollView, Dimensions } from 'react-native';
import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { API } from '../config';

interface SystemStats {
    cpu: number;
    ram: number;
    up: number;
    down: number;
    storageTotal: number;
    storageAvailable: number;
}

export default function SystemStatsTab() {
    const [stats, setStats] = useState<SystemStats | null>(null);
    const [online, setOnline] = useState(false);
    const pollRef = useRef<any>(undefined);

    const fetchStats = async () => {
        try {
            const token = await AsyncStorage.getItem('drivenet_token');
            const res = await axios.get(`${API}/api/fs/stats`, {
                headers: { Authorization: `Bearer ${token}` }
            });
            if (res.data && !res.data.error) {
                setStats(res.data);
                setOnline(true);
            } else {
                setOnline(false);
            }
        } catch {
            setOnline(false);
        }
    };

    useEffect(() => {
        fetchStats();
        pollRef.current = setInterval(fetchStats, 2000);
        return () => clearInterval(pollRef.current);
    }, []);

    const formatBytes = (b: number) => {
        if (!b || b <= 0) return '0 B';
        const k = 1024, s = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(b) / Math.log(k));
        return parseFloat((b / Math.pow(k, i)).toFixed(1)) + ' ' + s[i];
    };

    const renderCard = (title: string, value: string, sub?: string) => (
        <View style={styles.card}>
            <Text style={styles.cardTitle}>{title}</Text>
            <Text style={styles.cardValue}>{value}</Text>
            {sub && <Text style={styles.cardSub}>{sub}</Text>}
        </View>
    );

    return (
        <ScrollView style={styles.container}>
            <View style={styles.statusBox}>
                <View style={[styles.statusDot, { backgroundColor: online ? '#00e676' : '#ff4655' }]} />
                <Text style={styles.statusText}>AGENT {online ? 'ONLINE' : 'OFFLINE'}</Text>
            </View>

            {stats ? (
                <View style={styles.grid}>
                    {renderCard('CPU USAGE', `${stats.cpu}%`)}
                    {renderCard('RAM USAGE', `${stats.ram}%`)}
                    {renderCard('NETWORK UP', `${formatBytes(stats.up)}/s`)}
                    {renderCard('NETWORK DOWN', `${formatBytes(stats.down)}/s`)}
                    {renderCard('STORAGE', formatBytes(stats.storageAvailable), `of ${formatBytes(stats.storageTotal)} FREE`)}
                </View>
            ) : (
                <View style={styles.emptyContainer}>
                    <Text style={styles.emptyText}>WAITING FOR SENSOR DATA...</Text>
                </View>
            )}
        </ScrollView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0e0e0e',
        padding: 16,
    },
    statusBox: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 16,
        backgroundColor: '#1a1a1a',
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#333',
        marginVertical: 16,
        alignSelf: 'center',
    },
    statusDot: {
        width: 10,
        height: 10,
        borderRadius: 5,
        marginRight: 10,
    },
    statusText: {
        color: '#fff',
        fontSize: 12,
        fontWeight: 'bold',
        letterSpacing: 2,
    },
    grid: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        justifyContent: 'space-between',
    },
    card: {
        width: '48%',
        backgroundColor: '#141414',
        padding: 20,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#222',
        marginBottom: 16,
        alignItems: 'center',
    },
    cardTitle: {
        color: '#64748b',
        fontSize: 9,
        fontWeight: 'bold',
        letterSpacing: 1,
        marginBottom: 8,
    },
    cardValue: {
        color: '#ff4655',
        fontSize: 18,
        fontWeight: '900',
    },
    cardSub: {
        color: '#94a3b8',
        fontSize: 8,
        marginTop: 4,
        letterSpacing: 1,
    },
    emptyContainer: {
        padding: 40,
        alignItems: 'center',
    },
    emptyText: {
        color: '#64748b',
        fontSize: 11,
        fontWeight: 'bold',
        letterSpacing: 2,
    },
});
