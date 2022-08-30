require "ruby2d"

### WINDOW SETUP ###

set title: "Raycaster",
    background: "#555555",
    width: 1024, 
    height: 512,
    resizable: false


### MAP ###

MAP_BLOCKS_X = 8
MAP_BLOCKS_Y = 8
MAP_BLOCK_SIZE = 64
MAP_BLOCK_BIT_SHIFT = 6 # used to find nearest multiply of MAP_BLOCK_SIZE

MAP = [
  1, 1, 1, 1, 1, 1, 1, 1,
  1, 0, 2, 0, 0, 0, 0, 1,
  1, 0, 2, 0, 0, 0, 0, 1,
  1, 0, 2, 0, 0, 0, 0, 1,
  1, 0, 0, 0, 0, 0, 0, 1,
  1, 0, 0, 0, 0, 3, 0, 1,
  1, 0, 0, 0, 0, 0, 0, 1,
  1, 1, 1, 1, 1, 1, 1, 1,
].freeze

BLOCK_COLORS = {
  0 => "black",
  1 => "red",
  2 => "green",
  3 => "blue"
}.freeze

# Draw the map
(0...MAP_BLOCKS_Y).each do |n_row|
  (0...MAP_BLOCKS_X).each do |n_col|
    block_idx = (n_row * MAP_BLOCKS_X) + n_col
    block_x = n_col * MAP_BLOCK_SIZE
    block_y = n_row * MAP_BLOCK_SIZE

    Square.new(
      x: block_x + 1, # +1 leaves space for block borders
      y: block_y + 1, # +1 leaves space for block borders
      size: MAP_BLOCK_SIZE - 2,# -2 leaves space for block borders
      color: BLOCK_COLORS[MAP[block_idx]]
    )
  end
end


### PLAYER ###

PLAYER_SIZE = 1

@player = Square.new(x: 300, y: 300, size: PLAYER_SIZE, color: "yellow")
@p_angle = 0 # radians

def update_player_deltas
  @p_dx = Math.cos(@p_angle) * 5
  @p_dy = Math.sin(@p_angle) * 5
end


### INPUT ###

on :key_held do |event|
  case event.key
  when "a"
    @p_angle -= 0.1
    @p_angle = Math::PI*2 if @p_angle < 0
    # @p_angle += Math::PI*2 if @p_angle < 0
    update_player_deltas
  when "d"
    @p_angle += 0.1
    @p_angle = 0 if @p_angle > Math::PI * 2
    # @p_angle -= Math::PI * 2 if @p_angle > Math::PI * 2
    update_player_deltas
  when "w"
    @player.x += @p_dx
    @player.y += @p_dy
  when "s"
    @player.x -= @p_dx
    @player.y -= @p_dy
  end
end


### RAY CASTING

PI_2 = Math::PI / 2
PI_3 = 3 * Math::PI / 2
DR = 0.0174533 # one degree in radians

FOV = 60
N_RAYS = 60
RAYCAST_STEP = (FOV / N_RAYS) * DR

V_HIT_COLOR = "#ee0000"
H_HIT_COLOR = "#aa0000"

class Ray < Line
  def initialize(*)
    super
  end

  attr_accessor :distance, :angle

  def angle=(value)
    if value < 0
      value += 2 * Math::PI
    elsif value > 2 * Math::PI
      value -= 2 * Math::PI
    end

    @angle = value
  end
end

@rays = (1..N_RAYS).map { Ray.new(color: "green", width: 1) }

# finds nearest multiple of MAP_BLOCK_SIZE that is lower than y
def nearest_block(y)
  (y.to_i >> MAP_BLOCK_BIT_SHIFT) << MAP_BLOCK_BIT_SHIFT
end

def dist(ax, ay, bx, by, angle)
  Math.sqrt((bx - ax)**2 + (by - ay)**2) # pytaghoras in action
end

def find_horizontal_hit(ray_angle)
  depth = 0 # how far the ray looks
  atan = -1 / Math.tan(ray_angle)

  hit_dist = 1_000_000
  hit_x = @player.x
  hit_y = @player.y

  if ray_angle == 0 || ray_angle == Math::PI # looking straight left/right - no intersects
    ray_y = @player.y
    ray_x = @player.x
    depth = MAP_BLOCKS_Y
  elsif ray_angle > Math::PI # looking up
    ray_y = nearest_block(@player.y) - 0.0001 # so that we check the "lower" boundary of the blocks above
    ray_x = (@player.y - ray_y) * atan + @player.x
    y_offset = -MAP_BLOCK_SIZE
    x_offset = -y_offset * atan
  else # looking down
    ray_y = nearest_block(@player.y) + MAP_BLOCK_SIZE
    ray_x = (@player.y - ray_y) * atan + @player.x
    y_offset = MAP_BLOCK_SIZE
    x_offset = -y_offset * atan
  end

  while depth < MAP_BLOCKS_Y
    m_x = ray_x.to_i >> MAP_BLOCK_BIT_SHIFT # same as ray_x / 64
    m_y = ray_y.to_i >> MAP_BLOCK_BIT_SHIFT # same as ray_y / 64
    m_pos = m_y * MAP_BLOCKS_X + m_x

    if MAP[m_pos].to_i > 0 # ray has hit a wall
      depth = MAP_BLOCKS_Y # we're done

      # save the ray's final x and y
      hit_x = ray_x
      hit_y = ray_y
      hit_dist = dist(@player.x, @player.y, hit_x, hit_y, ray_angle)
      hit_block_type = MAP[m_pos]
    else
      # now we can just "jump" to the next gridline
      ray_x += x_offset
      ray_y += y_offset
      depth += 1
    end
  end

  [hit_x, hit_y, hit_dist, hit_block_type]
end

def find_vertical_hit(ray_angle)
  depth = 0 # depth of field - how far the ray can "see"
  ntan = -Math.tan(ray_angle)

  hit_dist = 1_000_000
  hit_x = @player.x
  hit_y = @player.y

  if ray_angle == PI_2 || ray_angle == PI_3 # looking straight up/down - no intersects
    ray_y = @player.y
    ray_x = @player.x
    depth = MAP_BLOCKS_X
  elsif ray_angle > PI_2 && ray_angle < PI_3 # looking left
    ray_x = nearest_block(@player.x) - 0.0001 # so that we check the "right" boundary of the blocks to the left
    ray_y = (@player.x - ray_x) * ntan + @player.y
    x_offset = -MAP_BLOCK_SIZE
    y_offset = -x_offset * ntan
  else # looking right
    ray_x = nearest_block(@player.x) + MAP_BLOCK_SIZE
    ray_y = (@player.x - ray_x) * ntan + @player.y
    x_offset = MAP_BLOCK_SIZE
    y_offset = -x_offset * ntan
  end

  while depth < MAP_BLOCKS_Y
    m_x = ray_x.to_i >> MAP_BLOCK_BIT_SHIFT # same as ray_x / 64
    m_y = ray_y.to_i >> MAP_BLOCK_BIT_SHIFT # same as ray_y / 64
    m_pos = m_y * MAP_BLOCKS_X + m_x

    if MAP[m_pos].to_i > 0 # ray has hit a wall
      depth = MAP_BLOCKS_Y # we're done

      # save the ray's x and y
      hit_x = ray_x
      hit_y = ray_y
      hit_dist = dist(@player.x, @player.y, hit_x, hit_y, ray_angle)
      hit_block_type = MAP[m_pos]
    else
      # now we can just "jump" to the next gridline
      ray_x += x_offset
      ray_y += y_offset
      depth += 1
    end
  end

  [hit_x, hit_y, hit_dist, hit_block_type]
end

def cast_ray(ray)
  ray.x1 = @player.x
  ray.y1 = @player.y

  h_hit_x, h_hit_y, h_dist, h_hit_block_type = find_horizontal_hit(ray.angle)
  v_hit_x, v_hit_y, v_dist, v_hit_block_type = find_vertical_hit(ray.angle)

  if (v_dist < h_dist)
    ray.x2 = v_hit_x
    ray.y2 = v_hit_y
    ray.distance = v_dist
    ray.color = BLOCK_COLORS[v_hit_block_type]
    ray.color.opacity = 0.9
  else
    ray.x2 = h_hit_x
    ray.y2 = h_hit_y
    ray.distance = h_dist
    ray.color = BLOCK_COLORS[h_hit_block_type]
    ray.color.opacity = 0.7
  end
end

def cast_rays
  start_angle = @p_angle - (FOV / 2) * DR

  @rays.each_with_index do |ray, i|
    ray.angle = start_angle + (i * RAYCAST_STEP)
    cast_ray(ray)
  end
end


### 3D SCENE RENDERING ###

SCENE_LEFT_OFFSET = 530 # 3D scene takes the right half of the window
WALL_LINE_WIDTH = 8

@wall_lines = (1..N_RAYS).map { Line.new(width: WALL_LINE_WIDTH) }

def draw_walls
  @rays.each_with_index do |ray, i|
    wline = @wall_lines[i]

    # fix warping
    a_diff = @p_angle - ray.angle
    a_diff += 2 * Math::PI if a_diff < 0
    a_diff -= 2 * Math::PI if a_diff > 2 * Math::PI
    dewarp = Math::cos(a_diff)

    # calculate line height
    line_height = (MAP_BLOCK_SIZE * 320) / (ray.distance * dewarp)
    line_height = 320 if line_height > 320

    # update line coordinates
    offset = 160 - (line_height / 2)
    wline.x1 = wline.x2 = SCENE_LEFT_OFFSET + (i * WALL_LINE_WIDTH)
    wline.y1 = offset
    wline.y2 = line_height + offset
    wline.color = ray.color
  end
end

### GAME LOOP ###

update_player_deltas

update do
  cast_rays
  draw_walls
end

show
