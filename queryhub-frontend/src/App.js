import React, { useState } from "react";

function App() {
  const [file, setFile] = useState(null);
  const [query, setQuery] = useState("");
  const [answer, setAnswer] = useState("");

  // Use window.location.hostname so it works on any network
  const BACKEND_URL = `http://${window.location.hostname}:8000`;

  const handleUpload = async () => {
    if (!file) return alert("Select a file first");
    try {
      const formData = new FormData();
      formData.append("file", file);

      console.log("Uploading to " + BACKEND_URL + "/upload");
      const res = await fetch(BACKEND_URL + "/upload", {
        method: "POST",
        body: formData,
      });
      
      if (!res.ok) {
        const errorText = await res.text();
        throw new Error(`HTTP ${res.status}: ${errorText}`);
      }
      
      const data = await res.json();
      alert(data.message || "File uploaded successfully");
    } catch (error) {
      console.error("Upload error:", error);
      alert(`Upload failed: ${error.message}`);
    }
  };

  const handleQuery = async () => {
    if (!query) return alert("Enter a query");
    try {
      console.log("Querying " + BACKEND_URL + "/ask");
      const res = await fetch(BACKEND_URL + "/ask", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query }),
      });
      
      if (!res.ok) {
        const errorText = await res.text();
        throw new Error(`HTTP ${res.status}: ${errorText}`);
      }
      
      const data = await res.json();
      setAnswer(data.answer || "No answer received");
    } catch (error) {
      console.error("Query error:", error);
      alert(`Query failed: ${error.message}`);
    }
  };

  return (
    <div style={{ padding: "2rem" }}>
      <h2>Upload File</h2>
      <input type="file" onChange={(e) => setFile(e.target.files[0])} />
      <button onClick={handleUpload}>Upload</button>

      <h2>Ask a Question</h2>
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        style={{ width: "300px" }}
      />
      <button onClick={handleQuery}>Ask</button>

      {answer && (
        <div style={{ marginTop: "1rem" }}>
          <strong>Answer:</strong>
          <p>{answer}</p>
        </div>
      )}
    </div>
  );
}

export default App;
