import React, { useState, useEffect } from 'react';
import { View, Text, FlatList, TouchableOpacity, StyleSheet, ActivityIndicator, Alert, Modal, TextInput } from 'react-native';
import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import * as DocumentPicker from 'expo-document-picker';
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

    const [promptVisible, setPromptVisible] = useState(false);
    const [promptType, setPromptType] = useState<'folder' | 'rename'>('folder');
    const [promptText, setPromptText] = useState('');
    const [targetItem, setTargetItem] = useState<FileItem | null>(null);

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

    const handleUpload = async () => {
        try {
            const result = await DocumentPicker.getDocumentAsync({ copyToCacheDirectory: true });
            if (result.canceled) return;

            const file = result.assets[0];
            const uploadId = file.uri;
            setLoading(true);

            const base64 = await FileSystem.readAsStringAsync(file.uri, { encoding: 'base64' });
            const CHUNK_SIZE = 1024 * 1024; // 1MB chunks
            const headers = await authHeader();

            if (base64.length === 0) {
                await axios.post(`${API}/api/fs/upload_chunk`, {
                    uploadId, path: currentPath, name: file.name, chunk: '', isFirst: true, isLast: true
                }, { headers });
            } else {
                for (let i = 0; i < base64.length; i += CHUNK_SIZE) {
                    const chunk = base64.substring(i, i + CHUNK_SIZE);
                    const isFirst = i === 0;
                    const isLast = (i + CHUNK_SIZE) >= base64.length;
                    await axios.post(`${API}/api/fs/upload_chunk`, {
                        uploadId, path: currentPath, name: file.name, chunk, isFirst, isLast
                    }, { headers });
                }
            }
            fetchFiles(currentPath);
        } catch (e) {
            Alert.alert('Upload Error', 'Failed to upload file');
        } finally {
            setLoading(false);
        }
    };

    const handleDelete = (item: FileItem) => {
        Alert.alert('Delete', `Are you sure you want to delete ${item.name}?`, [
            { text: 'Cancel', style: 'cancel' },
            {
                text: 'Delete', style: 'destructive', onPress: async () => {
                    setLoading(true);
                    try {
                        const headers = await authHeader();
                        const reqPath = currentPath ? `${currentPath}/${item.name}` : item.name;
                        await axios.delete(`${API}/api/fs/delete`, { headers, data: { items: [reqPath] } });
                        fetchFiles(currentPath);
                    } catch {
                        Alert.alert('Error', 'Failed to delete');
                        setLoading(false);
                    }
                }
            }
        ]);
    };

    const handlePromptSubmit = async () => {
        if (!promptText.trim()) return;
        setPromptVisible(false);
        setLoading(true);
        try {
            const headers = await authHeader();
            if (promptType === 'folder') {
                const reqPath = currentPath ? `${currentPath}/${promptText}` : promptText;
                await axios.post(`${API}/api/fs/folder`, { path: reqPath }, { headers });
            } else if (promptType === 'rename' && targetItem) {
                const oldPath = currentPath ? `${currentPath}/${targetItem.name}` : targetItem.name;
                const newPath = currentPath ? `${currentPath}/${promptText}` : promptText;
                await axios.post(`${API}/api/fs/rename`, { oldPath, newPath }, { headers });
            }
            fetchFiles(currentPath);
        } catch {
            Alert.alert('Error', 'Action failed');
            setLoading(false);
        }
    };

    const openRename = (item: FileItem) => {
        setTargetItem(item);
        setPromptText(item.name);
        setPromptType('rename');
        setPromptVisible(true);
    };

    const openNewFolder = () => {
        setPromptText('');
        setPromptType('folder');
        setPromptVisible(true);
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
        <View style={styles.fileRow}>
            <TouchableOpacity style={styles.fileRowBtn} onPress={() => handleFileClick(item)}>
                <Text style={styles.icon}>{item.is_dir ? '📁' : '📄'}</Text>
                <View style={styles.fileInfo}>
                    <Text style={styles.fileName} numberOfLines={1}>{item.name}</Text>
                    <Text style={styles.fileMeta}>
                        {item.is_dir ? 'DIR' : formatSize(item.size)} • {new Date(item.modified).toLocaleDateString()}
                    </Text>
                </View>
            </TouchableOpacity>
            <View style={styles.actions}>
                <TouchableOpacity style={styles.actionBtn} onPress={() => openRename(item)}>
                    <Text style={styles.actionText}>✎</Text>
                </TouchableOpacity>
                <TouchableOpacity style={styles.actionBtn} onPress={() => handleDelete(item)}>
                    <Text style={styles.actionText}>✕</Text>
                </TouchableOpacity>
            </View>
        </View>
    );

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.pathTitle} numberOfLines={1} ellipsizeMode={'head'}>/{currentPath || 'ROOT'}</Text>
                <View style={styles.headerActions}>
                    <TouchableOpacity style={styles.refreshBtn} onPress={openNewFolder}>
                        <Text style={styles.refreshText}>+ FOLD</Text>
                    </TouchableOpacity>
                    <TouchableOpacity style={styles.refreshBtn} onPress={handleUpload}>
                        <Text style={styles.refreshText}>↑ UPL</Text>
                    </TouchableOpacity>
                    <TouchableOpacity style={styles.refreshBtn} onPress={() => fetchFiles(currentPath)}>
                        <Text style={styles.refreshText}>↻</Text>
                    </TouchableOpacity>
                </View>
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

            <Modal visible={promptVisible} transparent animationType="fade">
                <View style={styles.modalBg}>
                    <View style={styles.promptBox}>
                        <Text style={styles.promptTitle}>{promptType === 'folder' ? 'NEW FOLDER' : 'RENAME'}</Text>
                        <TextInput
                            style={styles.promptInput}
                            value={promptText}
                            onChangeText={setPromptText}
                            autoFocus
                            placeholder="Enter name"
                            placeholderTextColor="#666"
                        />
                        <View style={styles.promptRow}>
                            <TouchableOpacity style={styles.promptBtn} onPress={() => setPromptVisible(false)}>
                                <Text style={styles.promptBtnText}>CANCEL</Text>
                            </TouchableOpacity>
                            <TouchableOpacity style={[styles.promptBtn, { borderLeftColor: '#ff4655' }]} onPress={handlePromptSubmit}>
                                <Text style={styles.promptBtnText}>CONFIRM</Text>
                            </TouchableOpacity>
                        </View>
                    </View>
                </View>
            </Modal>
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
    headerActions: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    actionBtn: {
        padding: 12,
        marginLeft: 4,
    },
    actionText: {
        color: '#64748b',
        fontSize: 18,
    },
    fileRowBtn: {
        flex: 1,
        flexDirection: 'row',
        alignItems: 'center',
    },
    actions: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    modalBg: {
        flex: 1,
        backgroundColor: 'rgba(0,0,0,0.8)',
        justifyContent: 'center',
        alignItems: 'center',
        padding: 24,
    },
    promptBox: {
        backgroundColor: '#1a1a1a',
        width: '100%',
        borderRadius: 8,
        padding: 24,
        borderWidth: 1,
        borderColor: '#333',
    },
    promptTitle: {
        color: '#fff',
        fontSize: 12,
        fontWeight: 'bold',
        letterSpacing: 2,
        marginBottom: 16,
    },
    promptInput: {
        backgroundColor: '#0e0e0e',
        color: '#fff',
        borderWidth: 1,
        borderColor: '#333',
        padding: 12,
        borderRadius: 4,
        marginBottom: 24,
    },
    promptRow: {
        flexDirection: 'row',
        justifyContent: 'flex-end',
        gap: 12,
    },
    promptBtn: {
        paddingVertical: 8,
        paddingHorizontal: 16,
        borderWidth: 1,
        borderColor: '#333',
        backgroundColor: '#0e0e0e',
        marginLeft: 8,
    },
    promptBtnText: {
        color: '#fff',
        fontSize: 10,
        fontWeight: 'bold',
        letterSpacing: 1,
    }
});
