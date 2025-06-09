import React, { useState } from 'react';
import axios from 'axios';

export default function UploadForm() {
  const [file, setFile] = useState(null);
  const [url, setUrl] = useState('');

  const handleUpload = async () => {
    const formData = new FormData();
    formData.append('file', file);

    const res = await axios.post('/api/upload', formData, {
      headers: { 'Content-Type': 'multipart/form-data' }
    });

    setUrl(res.data.url);
  };

  return (
    <div>
      <input type="file" onChange={(e) => setFile(e.target.files[0])} />
      <button onClick={handleUpload}>Upload</button>
      {url && <img src={url} alt="Uploaded" />}
    </div>
  );
}