'use strict';
// Что умеем читать (in) и во что превращать (out)
const KINDS = {
  image:  { title: 'Фото',        in: ['heic','jpg','png','webp','gif','tiff','bmp','avif'],
            out: ['jpg','png','webp','gif','tiff','bmp','avif','pdf'] },
  audio:  { title: 'Музыка',      in: ['mp3','wav','flac','aac','m4a','ogg','opus','aiff','wma'],
            out: ['mp3','m4a','wav','flac','ogg','opus','aiff'] },
  video:  { title: 'Видео',       in: ['mp4','mov','mkv','avi','webm','m4v','flv','wmv','mpg'],
            out: ['mp4','mov','mkv','avi','wmv','webm','gif','mp3','m4a','wav'] },
  doc:    { title: 'Документы',   in: ['doc','docx','odt','rtf','txt','html'],
            out: ['pdf','docx','txt','html','epub','png','jpg','odt','rtf'] },
  sheet:  { title: 'Таблицы',     in: ['xls','xlsx','ods','csv'],
            out: ['pdf','xlsx','xls','ods','csv','html'] },
  slides: { title: 'Презентации', in: ['ppt','pptx','odp'],
            out: ['pdf','pptx','ppt','odp','png','jpg'] },
  pdf:    { title: 'PDF',         in: ['pdf'],
            out: ['docx','txt','jpg','png'] }
};
const DEFAULT_HIDDEN = { video: ['m4a', 'wav'] };
const DEFAULT_TARGET = { image: 'jpg', audio: 'mp3', video: 'mp4', doc: 'pdf', sheet: 'pdf', slides: 'pdf', pdf: 'docx' };
const ALIAS = { jpeg: 'jpg', tif: 'tiff', htm: 'html', heif: 'heic', aif: 'aiff', mpeg: 'mpg' };

const norm = (e) => { e = String(e || '').toLowerCase().replace(/^\./, ''); return ALIAS[e] || e; };
const kindOf = (ext) => {
  ext = norm(ext);
  return Object.keys(KINDS).find((k) => KINDS[k].in.includes(ext)) || null;
};

module.exports = { KINDS, DEFAULT_HIDDEN, DEFAULT_TARGET, norm, kindOf };
