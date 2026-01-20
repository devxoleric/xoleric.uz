const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const { createClient } = require('@supabase/supabase-js');
const Redis = require('ioredis');
const winston = require('winston');
const morgan = require('morgan');
const path = require('path');
require('dotenv').config();

// Import routes
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const postRoutes = require('./routes/posts');
const commentRoutes = require('./routes/comments');
const chatRoutes = require('./routes/chat');
const notificationRoutes = require('./routes/notifications');
const searchRoutes = require('./routes/search');
const analyticsRoutes = require('./routes/analytics');
const adminRoutes = require('./routes/admin');

// Import middleware
const authMiddleware = require('./middleware/auth');
const errorMiddleware = require('./middleware/error');
const validationMiddleware = require('./middleware/validation');

// Initialize Express app
const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: process.env.FRONTEND_URL || 'http://localhost:3000',
    credentials: true
  }
});

// Configure Winston logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: 'logs/combined.log' }),
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ]
});

// Initialize Supabase
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_KEY
);

// Initialize Redis
const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.'
});

// API rate limiting
const apiLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 60, // 60 requests per minute
  message: 'Too many API requests, please slow down.'
});

// Middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      imgSrc: ["'self'", "data:", "https:", "http:"],
      connectSrc: ["'self'", "https://jkjymmjwqlaictcbuhsy.supabase.co"],
    },
  },
  crossOriginEmbedderPolicy: false
}));
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true
}));
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));
app.use('/api/', apiLimiter);
app.use(limiter);

// Static files
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Socket.IO authentication and events
io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth.token;
    if (!token) {
      return next(new Error('Authentication error'));
    }

    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error || !user) {
      return next(new Error('Authentication error'));
    }

    socket.user = user;
    next();
  } catch (error) {
    next(new Error('Authentication error'));
  }
});

io.on('connection', (socket) => {
  logger.info(`User connected: ${socket.user.id}`);
  
  // Join user room
  socket.join(`user:${socket.user.id}`);
  
  // Mark user as online
  redis.sadd('online_users', socket.user.id);
  io.emit('user_online', socket.user.id);
  
  // Handle typing events
  socket.on('typing_start', ({ chatId }) => {
    socket.to(`user:${chatId}`).emit('typing_start', {
      userId: socket.user.id,
      chatId: socket.user.id
    });
  });
  
  socket.on('typing_stop', ({ chatId }) => {
    socket.to(`user:${chatId}`).emit('typing_stop', { chatId: socket.user.id });
  });
  
  // Handle messages
  socket.on('send_message', async (messageData) => {
    try {
      const { data: message, error } = await supabase
        .from('messages')
        .insert([{
          ...messageData,
          sender_id: socket.user.id
        }])
        .select()
        .single();
      
      if (error) throw error;
      
      // Send to receiver
      io.to(`user:${messageData.receiver_id}`).emit('new_message', message);
      
      // Send notification
      const { error: notifError } = await supabase
        .from('notifications')
        .insert([{
          user_id: messageData.receiver_id,
          type: 'message',
          actor_id: socket.user.id,
          message_id: message.id,
          read: false,
          created_at: new Date().toISOString()
        }]);
      
      if (notifError) logger.error('Notification error:', notifError);
      
    } catch (error) {
      logger.error('Message send error:', error);
      socket.emit('error', { message: 'Failed to send message' });
    }
  });
  
  // Handle post events
  socket.on('new_post', async (post) => {
    try {
      // Notify followers
      const { data: followers } = await supabase
        .from('follows')
        .select('follower_id')
        .eq('following_id', socket.user.id);
      
      if (followers && followers.length > 0) {
        followers.forEach(follower => {
          io.to(`user:${follower.follower_id}`).emit('new_post_notification', {
            post,
            user: socket.user
          });
        });
      }
    } catch (error) {
      logger.error('Post notification error:', error);
    }
  });
  
  // Handle disconnect
  socket.on('disconnect', () => {
    logger.info(`User disconnected: ${socket.user.id}`);
    redis.srem('online_users', socket.user.id);
    io.emit('user_offline', socket.user.id);
  });
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', authMiddleware, userRoutes);
app.use('/api/posts', authMiddleware, postRoutes);
app.use('/api/comments', authMiddleware, commentRoutes);
app.use('/api/chat', authMiddleware, chatRoutes);
app.use('/api/notifications', authMiddleware, notificationRoutes);
app.use('/api/search', searchRoutes);
app.use('/api/analytics', authMiddleware, analyticsRoutes);
app.use('/api/admin', authMiddleware, adminRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Error handling middleware
app.use(errorMiddleware);

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Route not found',
    path: req.originalUrl
  });
});

// Global error handler
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (error) => {
  logger.error('Uncaught Exception:', error);
  process.exit(1);
});

// Start server
const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  logger.info(`Server running on port ${PORT}`);
  logger.info(`Environment: ${process.env.NODE_ENV}`);
});

module.exports = { app, server, io, supabase, redis, logger };
