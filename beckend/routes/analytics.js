const express = require('express');
const router = express.Router();
const { supabase } = require('../config/database');
const authMiddleware = require('../middleware/auth');
const adminMiddleware = require('../middleware/admin');

// Get platform statistics
router.get('/stats', authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const today = new Date();
    const weekAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
    const monthAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);

    // Get user statistics
    const { count: totalUsers } = await supabase
      .from('users')
      .select('*', { count: 'exact', head: true });

    const { count: newUsersThisWeek } = await supabase
      .from('users')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', weekAgo.toISOString());

    const { count: activeUsersThisWeek } = await supabase
      .from('users')
      .select('*', { count: 'exact', head: true })
      .gte('last_seen', weekAgo.toISOString());

    // Get post statistics
    const { count: totalPosts } = await supabase
      .from('posts')
      .select('*', { count: 'exact', head: true });

    const { count: newPostsToday } = await supabase
      .from('posts')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', today.toISOString().split('T')[0]);

    // Get engagement statistics
    const { data: likesData } = await supabase
      .from('likes')
      .select('created_at')
      .gte('created_at', monthAgo.toISOString());

    const { data: commentsData } = await supabase
      .from('comments')
      .select('created_at')
      .gte('created_at', monthAgo.toISOString());

    // Calculate daily engagement
    const dailyEngagement = {};
    [...likesData, ...commentsData].forEach(item => {
      const date = item.created_at.split('T')[0];
      dailyEngagement[date] = (dailyEngagement[date] || 0) + 1;
    });

    // Get top posts
    const { data: topPosts } = await supabase
      .from('posts')
      .select(`
        *,
        user:users(display_name, username)
      `)
      .order('metrics->likes', { ascending: false })
      .limit(10);

    // Get top hashtags
    const { data: topHashtags } = await supabase
      .from('hashtags')
      .select('*')
      .order('post_count', { ascending: false })
      .limit(10);

    res.json({
      users: {
        total: totalUsers,
        newThisWeek: newUsersThisWeek,
        activeThisWeek: activeUsersThisWeek,
        growthRate: ((newUsersThisWeek / totalUsers) * 100).toFixed(2)
      },
      posts: {
        total: totalPosts,
        newToday: newPostsToday,
        avgPostsPerUser: (totalPosts / totalUsers).toFixed(2)
      },
      engagement: {
        totalLikes: likesData.length,
        totalComments: commentsData.length,
        dailyEngagement,
        avgEngagementPerPost: ((likesData.length + commentsData.length) / totalPosts).toFixed(2)
      },
      topPosts,
      topHashtags,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Analytics error:', error);
    res.status(500).json({ error: 'Failed to fetch analytics' });
  }
});

// Get user activity timeline
router.get('/user/:userId/activity', authMiddleware, async (req, res) => {
  try {
    const userId = req.params.userId;
    const { startDate, endDate } = req.query;

    const query = supabase
      .from('analytics')
      .select('*')
      .eq('user_id', userId);

    if (startDate) query.gte('created_at', startDate);
    if (endDate) query.lte('created_at', endDate);

    const { data: activities, error } = await query
      .order('created_at', { ascending: false })
      .limit(100);

    if (error) throw error;

    // Group activities by date
    const activityByDate = {};
    activities.forEach(activity => {
      const date = activity.created_at.split('T')[0];
      if (!activityByDate[date]) {
        activityByDate[date] = {
          date,
          activities: [],
          count: 0
        };
      }
      activityByDate[date].activities.push(activity);
      activityByDate[date].count++;
    });

    const timeline = Object.values(activityByDate);

    res.json({
      userId,
      totalActivities: activities.length,
      timeline,
      period: {
        start: startDate || 'beginning',
        end: endDate || 'now'
      }
    });

  } catch (error) {
    console.error('User activity error:', error);
    res.status(500).json({ error: 'Failed to fetch user activity' });
  }
});

// Get real-time metrics
router.get('/realtime', authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const now = new Date();
    const hourAgo = new Date(now.getTime() - 60 * 60 * 1000);

    // Get real-time user count
    const { count: activeUsersNow } = await supabase
      .from('sessions')
      .select('*', { count: 'exact', head: true })
      .gte('last_activity', hourAgo.toISOString());

    // Get recent posts
    const { count: postsLastHour } = await supabase
      .from('posts')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', hourAgo.toISOString());

    // Get recent likes
    const { count: likesLastHour } = await supabase
      .from('likes')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', hourAgo.toISOString());

    // Get recent comments
    const { count: commentsLastHour } = await supabase
      .from('comments')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', hourAgo.toISOString());

    // Get server status
    const serverStatus = {
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      timestamp: now.toISOString()
    };

    res.json({
      realtime: {
        activeUsers: activeUsersNow,
        postsLastHour: postsLastHour,
        likesLastHour: likesLastHour,
        commentsLastHour: commentsLastHour,
        engagementRate: ((likesLastHour + commentsLastHour) / (postsLastHour || 1)).toFixed(2)
      },
      server: serverStatus,
      timestamp: now.toISOString()
    });

  } catch (error) {
    console.error('Realtime metrics error:', error);
    res.status(500).json({ error: 'Failed to fetch realtime metrics' });
  }
});

module.exports = router;
