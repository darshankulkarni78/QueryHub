import os
import tempfile
from typing import List
from docx import Document as Docx
import PyPDF2

def save_upload_to_tmp(upload_file) -> str:
    suffix = os.path.splitext(upload_file.filename)[1]
    fd, path = tempfile.mkstemp(suffix=suffix)
    with os.fdopen(fd, "wb") as f:
        f.write(upload_file.file.read())
    return path

def extract_text_from_file(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext in [".txt", ".md"]:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    if ext in [".docx"]:
        doc = Docx(path)
        return "\n".join(p.text for p in doc.paragraphs)
    if ext in [".pdf"]:
        text = []
        with open(path, "rb") as f:
            reader = PyPDF2.PdfReader(f)
            for p in reader.pages:
                text.append(p.extract_text() or "")
        return "\n".join(text)
    with open(path, "rb") as f:
        return f.read().decode("utf-8", errors="ignore")

def chunk_text(text: str, chunk_size: int, overlap: int) -> List[str]:
    chunks = []
    start = 0
    text_len = len(text)
    while start < text_len:
        end = start + chunk_size
        chunk = text[start:end]
        chunks.append(chunk.strip())
        start = end - overlap
        if start < 0:
            start = 0
    return [c for c in chunks if c]
