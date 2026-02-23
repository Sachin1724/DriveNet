import React, { useState } from 'react';
import { View, Text, Modal, TouchableOpacity, StyleSheet, ActivityIndicator, Image, ScrollView } from 'react-native';
import { Video, ResizeMode } from 'expo-av';
import { WebView } from 'react-native-webview';

interface FilePreviewModalProps {
    visible: boolean;
    onClose: () => void;
    url: string | null;
    name: string;
    type: 'image' | 'video' | 'pdf' | 'text' | null;
    textData?: string;
    videoQuality?: 'original' | 'low';
    onQualityChange?: (q: 'original' | 'low') => void;
}

export default function FilePreviewModal({ visible, onClose, url, name, type, textData, videoQuality, onQualityChange }: FilePreviewModalProps) {
    const [loading, setLoading] = useState(true);

    return (
        <Modal visible={visible} transparent={true} animationType="fade" onRequestClose={onClose}>
            <View style={styles.overlay}>
                <View style={styles.container}>
                    <View style={styles.header}>
                        <View style={styles.titleContainer}>
                            <Text style={styles.title} numberOfLines={1}>{name}</Text>
                            {type === 'video' && onQualityChange && (
                                <View style={styles.qualityNav}>
                                    <TouchableOpacity onPress={() => onQualityChange('original')} style={[styles.qBtn, videoQuality === 'original' && styles.qBtnActive]}>
                                        <Text style={[styles.qText, videoQuality === 'original' && styles.qTextActive]}>Original</Text>
                                    </TouchableOpacity>
                                    <TouchableOpacity onPress={() => onQualityChange('low')} style={[styles.qBtn, videoQuality === 'low' && styles.qBtnActive]}>
                                        <Text style={[styles.qText, videoQuality === 'low' && styles.qTextActive]}>Data Saver</Text>
                                    </TouchableOpacity>
                                </View>
                            )}
                        </View>
                        <TouchableOpacity onPress={onClose} style={styles.closeBtn}>
                            <Text style={styles.closeText}>X</Text>
                        </TouchableOpacity>
                    </View>

                    <View style={styles.content}>
                        {loading && type !== 'text' && (
                            <ActivityIndicator size="large" color="#ff4655" style={styles.loader} />
                        )}

                        {type === 'image' && url && (
                            <Image source={{ uri: url }} style={styles.media} resizeMode="contain" onLoadEnd={() => setLoading(false)} />
                        )}
                        {type === 'video' && url && (
                            <Video
                                source={{ uri: url }}
                                style={styles.media}
                                useNativeControls
                                resizeMode={ResizeMode.CONTAIN}
                                onLoad={() => setLoading(false)}
                            />
                        )}
                        {type === 'pdf' && url && (
                            <WebView source={{ uri: url }} style={styles.webview} onLoadEnd={() => setLoading(false)} />
                        )}
                        {type === 'text' && (
                            <ScrollView style={styles.textContainer}>
                                <Text style={styles.textContent}>{textData}</Text>
                            </ScrollView>
                        )}
                    </View>
                </View>
            </View>
        </Modal>
    );
}

const styles = StyleSheet.create({
    overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.95)', justifyContent: 'center', padding: 16 },
    container: { backgroundColor: '#141414', borderRadius: 8, borderWidth: 1, borderColor: '#333', overflow: 'hidden', maxHeight: '95%' },
    header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 12, borderBottomWidth: 1, borderBottomColor: '#222' },
    titleContainer: { flex: 1, flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8 },
    title: { color: '#94a3b8', fontSize: 12, fontWeight: 'bold', fontFamily: 'monospace', maxWidth: 150 },
    qualityNav: { flexDirection: 'row', borderWidth: 1, borderColor: '#333', borderRadius: 4, overflow: 'hidden' },
    qBtn: { paddingHorizontal: 8, paddingVertical: 4 },
    qBtnActive: { backgroundColor: '#ff4655' },
    qText: { color: '#64748b', fontSize: 9, fontWeight: 'bold', textTransform: 'uppercase' },
    qTextActive: { color: '#fff' },
    closeBtn: { paddingHorizontal: 12, paddingVertical: 6, borderWidth: 1, borderColor: '#333' },
    closeText: { color: '#64748b', fontSize: 12, fontWeight: 'bold' },
    content: { minHeight: 300 },
    loader: { position: 'absolute', top: '50%', left: '50%', marginLeft: -18, marginTop: -18, zIndex: 10 },
    media: { width: '100%', height: 400 },
    webview: { width: '100%', height: 500, backgroundColor: '#fff' },
    textContainer: { padding: 16, height: 500, backgroundColor: '#0f0f0f' },
    textContent: { color: '#cbd5e1', fontSize: 12, fontFamily: 'monospace' },
});
