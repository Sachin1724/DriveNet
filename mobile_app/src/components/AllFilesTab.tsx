import React, { useState, useEffect } from 'react';
import { View, Text, FlatList, TouchableOpacity, StyleSheet, ActivityIndicator } from 'react-native';
import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { API } from '../config';
import FilePreviewModal from './FilePreviewModal';

export interface FileItem {
    name: string;
    is_dir: boolean;
    size: number;
    modified: string;
}

export default function AllFilesTab() {
    const [files, setFiles] = useState<FileItem[]>([]);
    const [currentPath, setCurrentPath] = useState('');
    const [loading, setLoading] = useState(false);

    // Preview State
    const [previewVisible, setPreviewVisible] = useState(false);
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);
    const [previewName, setPreviewName] = useState<string>('');
    const [previewType, setPreviewType] = useState<'image' | 'video' | 'pdf' | 'text' | null>(null);
    const [previewText, setPreviewText] = useState<string>('');
    const [videoQuality, setVideoQuality] = useState<'original' | 'low'>('original');

    useEffect(() => {
        fetchFiles(currentPath);
    }, []);

    const authHeader = async () => {
        const token = await AsyncStorage.getItem('drivenet_token');
        return { Authorization: `Bearer ${token}` };
    };

    const fetchFiles = async (path: string) => {
        setLoading(true);
        try {
            const headers = await authHeader();
            const res = await axios.get(`${API}/api/fs/list?path=${encodeURIComponent(path)}`, { headers });
            setFiles(res.data.files || []);
            setCurrentPath(path);
        } catch (e) {
            console.log('Fetch error', e);
        }
        setLoading(false);
    };

    const formatSize = (bytes: number) => {
        if (bytes === 0) return '0 B';
        const k = 1024, sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    };

    const navigateUp = () => {
        if (!currentPath) return;
        const parts = currentPath.split('/');
        parts.pop();
        fetchFiles(parts.join('/'));
    };

    const getExt = (name: string) => name.split('.').pop()?.toLowerCase() ?? '';
    const isImage = (name: string) => ['jpg', 'jpeg', 'png', 'gif', 'webp'].includes(getExt(name));
    const isVideo = (name: string) => ['mp4', 'webm', 'mov', 'avi', 'mkv'].includes(getExt(name));
    const isPDF = (name: string) => getExt(name) === 'pdf';
    const isText = (name: string) => ['txt', 'md', 'json', 'csv', 'js', 'ts', 'jsx', 'tsx', 'html', 'css', 'ini'].includes(getExt(name));

    const handleFileClick = async (item: FileItem) => {
        if (item.is_dir) {
            const next = currentPath ? `${currentPath}/${item.name}` : item.name;
            fetchFiles(next);
            return;
        }

        const rel = currentPath ? `${currentPath}/${item.name}` : item.name;
        const token = await AsyncStorage.getItem('drivenet_token') || '';

        if (isImage(item.name) || isVideo(item.name) || isPDF(item.name) || isText(item.name)) {
            setPreviewName(item.name);
            setPreviewUrl(null);
            setPreviewText('');
            setPreviewVisible(true);

            const isVid = isVideo(item.name);
            const isTxt = isText(item.name);
            setPreviewType(isImage(item.name) ? 'image' : isVid ? 'video' : isPDF(item.name) ? 'pdf' : 'text');

            if (isVid) {
                setPreviewUrl(`${API}/api/fs/video?path=${encodeURIComponent(rel)}&token=${token}&quality=${videoQuality}`);
            } else if (isTxt) {
                try {
                    const res = await axios.get(`${API}/api/fs/download?path=${encodeURIComponent(rel)}`, { headers: { Authorization: `Bearer ${token}` } });
                    setPreviewText(typeof res.data === 'string' ? res.data : JSON.stringify(res.data, null, 2));
                } catch { setPreviewText('Error loading document content.'); }
            } else {
                setPreviewUrl(`${API}/api/fs/download?path=${encodeURIComponent(rel)}&token=${token}`);
            }
        } else {
            // Native File Download via Expo FileSystem
            try {
                const fileUri = FileSystem.documentDirectory! + item.name;
                const downloadRes = await FileSystem.downloadAsync(
                    `${API}/api/fs/download?path=${encodeURIComponent(rel)}&token=${token}`,
                    fileUri
                );
                if (await Sharing.isAvailableAsync()) {
                    Sharing.shareAsync(downloadRes.uri);
                } else {
                    alert('Saved to device: ' + downloadRes.uri);
                }
            } catch (e) {
                alert('Failed to download file.');
            }
        }
    };

    const updateVideoQuality = (q: 'original' | 'low') => {
        setVideoQuality(q);
        const rel = currentPath ? `${currentPath}/${previewName}` : previewName;
        AsyncStorage.getItem('drivenet_token').then(token => {
            setPreviewUrl(`${API}/api/fs/video?path=${encodeURIComponent(rel)}&token=${token || ''}&quality=${q}`);
        });
    };

    const renderItem = ({ item }: { item: FileItem }) => (
        <TouchableOpacity style={styles.fileRow} onPress={() => handleFileClick(item)}>
            <Text style={styles.icon}>{item.is_dir ? '📁' : '📄'}</Text>
            <View style={styles.fileInfo}>
                <Text style={styles.fileName} numberOfLines={1}>{item.name}</Text>
                <Text style={styles.fileMeta}>
                    {item.is_dir ? 'DIR' : formatSize(item.size)} • {new Date(item.modified).toLocaleDateString()}
                </Text>
            </View>
        </TouchableOpacity>
    );

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.pathTitle}>PATH: /{currentPath}</Text>
                <TouchableOpacity style={styles.refreshBtn} onPress={() => fetchFiles(currentPath)}>
                    <Text style={styles.refreshText}>REFRESH</Text>
                </TouchableOpacity>
            </View>

            {currentPath ? (
                <TouchableOpacity style={styles.backBtn} onPress={navigateUp}>
                    <Text style={styles.backText}>← UP</Text>
                </TouchableOpacity>
            ) : null}

            {loading ? (
                <View style={styles.loader}>
                    <ActivityIndicator size="large" color="#ff4655" />
                    <Text style={styles.loaderText}>SCANNING SECURE NODE...</Text>
                </View>
            ) : (
                <FlatList
                    data={files}
                    keyExtractor={item => item.name}
                    renderItem={renderItem}
                    ListEmptyComponent={
                        <View style={styles.emptyContainer}>
                            <Text style={styles.emptyText}>NO FILES FOUND OR AGENT OFFLINE</Text>
                        </View>
                    }
                />
            )}

            <FilePreviewModal
                visible={previewVisible}
                onClose={() => setPreviewVisible(false)}
                url={previewUrl}
                name={previewName}
                type={previewType}
                textData={previewText}
                videoQuality={videoQuality}
                onQualityChange={previewType === 'video' ? updateVideoQuality : undefined}
            />
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0e0e0e',
    },
    header: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: 16,
        borderBottomWidth: 1,
        borderBottomColor: '#222',
        backgroundColor: '#141414',
    },
    pathTitle: {
        fontSize: 10,
        fontWeight: 'bold',
        fontFamily: 'monospace',
        color: '#94a3b8',
    },
    refreshBtn: {
        borderWidth: 1,
        borderColor: '#333',
        paddingHorizontal: 8,
        paddingVertical: 4,
    },
    refreshText: {
        color: '#ff4655',
        fontSize: 9,
        fontWeight: 'bold',
        letterSpacing: 1,
    },
    backBtn: {
        padding: 12,
        borderBottomWidth: 1,
        borderBottomColor: '#222',
        backgroundColor: '#1a1a1a',
    },
    backText: {
        color: '#64748b',
        fontSize: 10,
        fontWeight: 'bold',
        letterSpacing: 1,
    },
    fileRow: {
        flexDirection: 'row',
        padding: 16,
        borderBottomWidth: 1,
        borderBottomColor: '#1a1a1a',
        alignItems: 'center',
    },
    icon: {
        fontSize: 24,
        marginRight: 16,
    },
    fileInfo: {
        flex: 1,
    },
    fileName: {
        color: '#cbd5e1',
        fontSize: 13,
        fontWeight: 'bold',
        marginBottom: 4,
    },
    fileMeta: {
        color: '#64748b',
        fontSize: 10,
        fontFamily: 'monospace',
    },
    loader: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    loaderText: {
        color: '#64748b',
        fontSize: 10,
        marginTop: 12,
        letterSpacing: 2,
        fontWeight: 'bold',
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
