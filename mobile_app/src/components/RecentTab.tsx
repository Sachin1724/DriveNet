import React, { useState, useCallback } from 'react';
import { View, Text, FlatList, StyleSheet } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useFocusEffect } from '@react-navigation/native';

export default function RecentTab() {
    const [activity, setActivity] = useState<any[]>([]);

    useFocusEffect(
        useCallback(() => {
            const loadActivity = async () => {
                const data = await AsyncStorage.getItem('dn_activity');
                if (data) setActivity(JSON.parse(data));
            };
            loadActivity();
        }, [])
    );

    const formatSize = (bytes: number) => {
        if (!bytes) return '0 B';
        const k = 1024, sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    };

    const renderItem = ({ item }: any) => (
        <View style={styles.row}>
            <Text style={styles.name} numberOfLines={1}>{item.name}</Text>
            <View style={[styles.badge, item.action === 'UPLOADED' ? styles.badgeGreen : styles.badgeRed]}>
                <Text style={[styles.badgeText, item.action === 'UPLOADED' ? styles.textGreen : styles.textRed]}>{item.action}</Text>
            </View>
            <Text style={styles.size}>{formatSize(item.size)}</Text>
        </View>
    );

    return (
        <View style={styles.container}>
            <FlatList
                data={activity}
                keyExtractor={(item, index) => index.toString()}
                renderItem={renderItem}
                ListEmptyComponent={
                    <View style={styles.empty}>
                        <Text style={styles.emptyText}>NO TRANSFERS YET</Text>
                    </View>
                }
            />
        </View>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#0e0e0e' },
    row: { flexDirection: 'row', padding: 16, borderBottomWidth: 1, borderBottomColor: '#1a1a1a', alignItems: 'center' },
    name: { flex: 1, color: '#cbd5e1', fontSize: 13, fontWeight: 'bold' },
    badge: { paddingHorizontal: 6, paddingVertical: 2, marginRight: 12 },
    badgeGreen: { backgroundColor: 'rgba(74, 222, 128, 0.1)' },
    badgeRed: { backgroundColor: 'rgba(239, 68, 68, 0.1)' },
    badgeText: { fontSize: 9, fontWeight: 'bold', letterSpacing: 1 },
    textGreen: { color: '#4ade80' },
    textRed: { color: '#ef4444' },
    size: { color: '#64748b', fontSize: 10, fontFamily: 'monospace', width: 60, textAlign: 'right' },
    empty: { padding: 40, alignItems: 'center' },
    emptyText: { color: '#64748b', fontSize: 11, fontWeight: 'bold', letterSpacing: 2 },
});
