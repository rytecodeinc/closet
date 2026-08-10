// worker.js - Cloudflare Worker for Redress Closet App Photo Storage
// Worker Name: redress-item-photos-api

export default {
  async fetch(request, env, ctx) {
    // CORS headers for all responses
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*', // Change to your app domain in production
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Max-Age': '86400',
    };

    // Handle preflight requests
    if (request.method === 'OPTIONS') {
      return new Response(null, { 
        status: 204,
        headers: corsHeaders 
      });
    }

    try {
      // Extract path from URL (format: /userId/itemId/photoId.jpg)
      const url = new URL(request.url);
      const path = url.pathname.slice(1); // Remove leading slash
      
      // Validate path format
      if (!path || path.split('/').length < 3) {
        return jsonResponse(
          { error: 'Invalid path format. Expected: userId/itemId/photoId.jpg' },
          400,
          corsHeaders
        );
      }

        // Extract userId from path
        const pathParts = path.split('/');
        const pathUserId = pathParts[0].toLowerCase(); // Normalize to lowercase for comparison

        // Validate authentication for write operations
        if (request.method !== 'GET') {
          const authHeader = request.headers.get('Authorization');
          if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return jsonResponse(
              { error: 'Missing or invalid Authorization header' },
              401,
              corsHeaders
            );
          }

          // Extract and validate JWT token
          const token = authHeader.substring(7); // Remove "Bearer " prefix
          const userId = await validateSupabaseJWT(token, env);
          
          if (!userId) {
            return jsonResponse(
              { error: 'Invalid or expired token' },
              401,
              corsHeaders
            );
          }

          // Normalize userId to lowercase for comparison (UUIDs can be case-insensitive)
          const normalizedUserId = String(userId).toLowerCase();
          const normalizedPathUserId = pathUserId.toLowerCase();

          // Redress suggestion collages live under the suggester's prefix. Recipients must
          // DELETE them after reject (authorized in-app via respond_to_outfit_suggestion).
          // Suggestion IDs are UUIDs; allow authenticated DELETE on that path shape only.
          const isOutfitSuggestionDelete =
            request.method === 'DELETE' &&
            pathParts.length >= 3 &&
            String(pathParts[1]).toLowerCase() === 'outfit-suggestions';

          // Verify user owns the path (case-insensitive comparison)
          if (normalizedUserId !== normalizedPathUserId && !isOutfitSuggestionDelete) {
            console.error(`User ID mismatch: JWT userId="${normalizedUserId}", path userId="${normalizedPathUserId}"`);
            return jsonResponse(
              { error: 'Forbidden: You can only access your own files' },
              403,
              corsHeaders
            );
          }
        }

      // Route to appropriate handler
      switch (request.method) {
        case 'GET':
          return await handleGet(path, env, corsHeaders);
        case 'PUT':
          return await handlePut(path, request, env, corsHeaders);
        case 'DELETE':
          return await handleDelete(path, env, corsHeaders);
        default:
          return jsonResponse(
            { error: 'Method not allowed' },
            405,
            corsHeaders
          );
      }
    } catch (error) {
      console.error('Worker error:', error);
      return jsonResponse(
        { error: 'Internal server error', message: error.message },
        500,
        corsHeaders
      );
    }
  },
};

/**
 * Validates Supabase JWT token and returns user ID
 */
async function validateSupabaseJWT(token, env) {
  try {
    // Call Supabase API to validate token
    const response = await fetch(`https://${env.SUPABASE_PROJECT_ID}.supabase.co/auth/v1/user`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'apikey': env.SUPABASE_ANON_KEY,
      },
    });

    if (!response.ok) {
      console.error(`Supabase auth API error: ${response.status} ${response.statusText}`);
      return null;
    }

    const user = await response.json();
    // Return user ID as string, normalized to lowercase
    if (user.id) {
      const normalizedId = String(user.id).toLowerCase();
      console.log(`✅ JWT validated, user ID: ${normalizedId}`);
      return normalizedId;
    }
    console.error('No user ID in Supabase response');
    return null;
  } catch (error) {
    console.error('JWT validation error:', error);
    return null;
  }
}

/**
 * Handles GET requests - retrieve photo from R2
 */
async function handleGet(path, env, corsHeaders) {
  try {
    const object = await env.R2_BUCKET.get(path);
    
    if (!object) {
      return jsonResponse(
        { error: 'File not found' },
        404,
        corsHeaders
      );
    }

    // Return file with appropriate headers
    const headers = {
      ...corsHeaders,
      'Content-Type': object.httpMetadata?.contentType || 'image/jpeg',
      'Content-Length': object.size.toString(),
      'Cache-Control': 'public, max-age=31536000, immutable', // Cache for 1 year
      'ETag': object.httpEtag || '',
    };

    return new Response(object.body, {
      status: 200,
      headers,
    });
  } catch (error) {
    console.error('GET error:', error);
    return jsonResponse(
      { error: 'Failed to retrieve file' },
      500,
      corsHeaders
    );
  }
}

/**
 * Handles PUT requests - upload photo to R2
 */
async function handlePut(path, request, env, corsHeaders) {
  try {
    // Validate content type
    const contentType = request.headers.get('Content-Type');
    if (!contentType || !contentType.startsWith('image/')) {
      return jsonResponse(
        { error: 'Invalid content type. Expected image/*' },
        400,
        corsHeaders
      );
    }

    // Check file size (limit to 5MB)
    const contentLength = request.headers.get('Content-Length');
    if (contentLength && parseInt(contentLength) > 5 * 1024 * 1024) {
      return jsonResponse(
        { error: 'File size exceeds 5MB limit' },
        413,
        corsHeaders
      );
    }

    // Read request body
    const body = await request.arrayBuffer();

    // Validate actual size
    if (body.byteLength > 5 * 1024 * 1024) {
      return jsonResponse(
        { error: 'File size exceeds 5MB limit' },
        413,
        corsHeaders
      );
    }

    // Upload to R2
    await env.R2_BUCKET.put(path, body, {
      httpMetadata: {
        contentType: contentType,
        cacheControl: 'public, max-age=31536000, immutable',
      },
      customMetadata: {
        uploadedAt: new Date().toISOString(),
      },
    });

    // Return success with public URL
    const publicUrl = `${env.WORKER_URL || request.url.split('/').slice(0, 3).join('/')}/${path}`;
    
    return jsonResponse(
      { 
        success: true,
        url: publicUrl,
        path: path,
      },
      200,
      corsHeaders
    );
  } catch (error) {
    console.error('PUT error:', error);
    return jsonResponse(
      { error: 'Failed to upload file' },
      500,
      corsHeaders
    );
  }
}

/**
 * Handles DELETE requests - remove photo from R2
 */
async function handleDelete(path, env, corsHeaders) {
  try {
    await env.R2_BUCKET.delete(path);
    
    return jsonResponse(
      { success: true, message: 'File deleted' },
      200,
      corsHeaders
    );
  } catch (error) {
    console.error('DELETE error:', error);
    return jsonResponse(
      { error: 'Failed to delete file' },
      500,
      corsHeaders
    );
  }
}

/**
 * Helper function to create JSON responses
 */
function jsonResponse(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  });
}

