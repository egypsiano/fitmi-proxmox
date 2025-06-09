const express = require('express');
const app = express();
const uploadRouter = require('./routes/upload');

app.use(express.json());
app.use('/api/upload', uploadRouter);

// Your other routes...

app.listen(5000, () => {
  console.log('Backend running on port 5000');
});