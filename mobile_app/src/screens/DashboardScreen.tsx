import React, { useState, useEffect } from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { TouchableOpacity, Text, StyleSheet } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Ionicons } from '@expo/vector-icons';

// Tabs
import AllFilesTab from '../components/AllFilesTab';
import RecentTab from '../components/RecentTab';
import SystemStatsTab from '../components/SystemStatsTab';

const Tab = createBottomTabNavigator();

export default function DashboardScreen({ navigation }: any) {
    const handleLogout = async () => {
        await AsyncStorage.removeItem('drivenet_token');
        navigation.replace('Login');
    };

    return (
        <Tab.Navigator
            screenOptions={{
                headerStyle: { backgroundColor: '#0e0e0e', elevation: 0, shadowOpacity: 0, borderBottomWidth: 1, borderBottomColor: '#222' },
                headerTitleStyle: { color: '#fff', fontSize: 12, fontWeight: '900', letterSpacing: 2 },
                tabBarStyle: { backgroundColor: '#0e0e0e', borderTopWidth: 1, borderTopColor: '#222', paddingBottom: 4 },
                tabBarActiveTintColor: '#ff4655',
                tabBarInactiveTintColor: '#64748b',
                tabBarLabelStyle: { fontSize: 10, fontWeight: 'bold', letterSpacing: 1 },
                headerRight: () => (
                    <TouchableOpacity onPress={handleLogout} style={styles.logoutBtn}>
                        <Text style={styles.logoutText}>DISCONNECT</Text>
                    </TouchableOpacity>
                )
            }}
        >
            <Tab.Screen
                name="All Files"
                component={AllFilesTab}
                options={{
                    title: 'DRIVE: ROOT',
                    tabBarIcon: ({ color, size }) => <Ionicons name="folder-open" size={size} color={color} />
                }}
            />
            <Tab.Screen
                name="Recent"
                component={RecentTab}
                options={{
                    title: 'ACTIVITY LOG',
                    tabBarIcon: ({ color, size }) => <Ionicons name="time" size={size} color={color} />
                }}
            />
            <Tab.Screen
                name="Stats"
                component={SystemStatsTab}
                options={{
                    title: 'SYSTEM TELEMETRY',
                    tabBarIcon: ({ color, size }) => <Ionicons name="pulse" size={size} color={color} />
                }}
            />
        </Tab.Navigator>
    );
}

const styles = StyleSheet.create({
    logoutBtn: {
        marginRight: 16,
        padding: 6,
        borderWidth: 1,
        borderColor: '#ff4655',
        backgroundColor: 'rgba(255, 70, 85, 0.1)',
    },
    logoutText: {
        color: '#ff4655',
        fontSize: 9,
        fontWeight: 'bold',
        letterSpacing: 1,
    }
});
