class Pathfinder
  class FaceReducer < Reducer

    private

    attr_reader :visited

    public

    def initialize g
      @visited = Set.new
      super g
    end

    def reduce
      modified! false
      visited.clear
      logger = Pathfinder.logger

      loop do
        face = find_a_face
        logger.debug(self.class.name) { "Found face: " }
        logger.debug(self.class.name) { face.to_s }
        break unless face
        begin
          v1, v2 = face.furthest_vertex_pair
          pair = face.longest_edge_multi_line_strings

          logger.debug(self.class.name) { "Furthest vergexes: #{ [v1, v2].map { |v| v.to_s }.join(' ') }" }
          next if too_far_apart? pair
          averaged_line = replace_long_linestrings *pair
          join_adjacents_to_averaged_line face, averaged_line
        rescue AssertionFailedException => e
          logger.warn(self.class.name) { e.to_s }
        end
      end

      logger.debug(self.class.name) { "#reduce returning modifcation status #{modified?}" }
      modified?
    end

    private

    def find_a_face
      logger = Pathfinder.logger

      logger.debug('find_a_face') { 'entry'}
      # logger.debug('find_a_face') { visited.map { |p| p.to_s }.join ' ' }
      graph.vertices.each do |start_vertex|
        logger.debug('find_a_face') { "Start Vertex: #{start_vertex}" }
        logger.debug('find_a_face') { "Visited? #{visited? start_vertex}"}
        next if visited? start_vertex
        face_vertices = traverse_face start_vertex
        next unless face_vertices
        visit! face_vertices

        if face_vertices.length < 3
          logger.warn('FaceReducer.find_a_face') {
            "Danger, found small face - #{face_vertices.map { |p| p.to_s }.join(' ')}" 
          }
          next
        end

        if face_vertices[1..-2] != face_vertices[1..-2].uniq
          logger.warn('FaceReducer.find_a_face') { "Danger, face has internal point duplication" }
          next
        end
        $stderr.puts "X" * 80
        $stderr.puts face_vertices

        return(Face.new(graph, face_vertices)) if(face_vertices)
      end
      logger.debug('find_a_face') { "returning nil, didn't find a face" }
      return nil
    end

    def traverse_face(start_v, current_v = start_v, accum = [])
      logger = Pathfinder.logger
      logger.debug('traverse_face') { "%s %s %s" % [ start_v, current_v, accum.length ] }
      return false if accum.length > 4
      return accum if current_v == start_v and accum.length > 0

      successors = Array(graph.successors current_v)
      (successors - [accum.last]).each do |next_v|
        face = traverse_face(start_v, next_v, accum + [current_v])
        return face if face
      end

      return false
    end

    def replace_long_linestrings mls1, mls2
      indexes = (indexes_for_multi_line_string(mls1) + indexes_for_multi_line_string(mls2)).sort
      averaged_line = average_line mls1, mls2

      logger = Pathfinder.logger
      logger.debug('replace_long_linestrings') { "Averaged Line: #{averaged_line}" }
      MultiLineString.break_line_string(averaged_line, indexes).each do |ls|
        add_edge ls
      end

      mls1.each { |ls| remove_edge ls }
      mls2.each { |ls| remove_edge ls }

      averaged_line
    end

    def average_line mls1, mls2
      logger = Pathfinder.logger

      ls1 = MultiLineString.ls_from_mls mls1
      ls2 = MultiLineString.ls_from_mls mls2
      averaged_line = LineString.average ls1, ls2
      # logger.debug(self.class.name) { "Created initial averaged line" }
      # logger.debug(self.class.name) { averaged_line.to_s }
      # logger.debug(self.class.name) { "Averaged line based on these linestrings" }
      # logger.debug(self.class.name) { ls1 }
      # logger.debug(self.class.name) { ls2 }

      averaged_line
    end

    def join_adjacents_to_averaged_line face, averaged_line
      logger = Pathfinder.logger
      factory = GeometryFactory.new PrecisionModel.new, 4326
      furthest_pair = face.furthest_vertex_pair

      for_removal = Set.new
      face.longest_edge_multi_line_strings.each do |mls|
        # logger.debug(self.class.name) { "Working with MLS item: " }
        # logger.debug(self.class.name) { mls.to_s }
        first_points = mls.map { |line| line.first } - furthest_pair
        first_points.each do |pt|
          # logger.debug(self.class.name) { "Working with pt: #{pt}" }
          index = mls.index pt
          # logger.debug(self.class.name) { "Index for new point on mls is: #{index}" }
          new_pt = averaged_line.point_at index
          # logger.debug(self.class.name) { "New Point: #{new_pt}" }
          face.off_face_edges(pt).each do |edge|
            # logger.debug(self.class.name) { "Off Face Edge: " }
            # logger.debug(self.class.name) { edge.to_s }
            r_pts = Array(edge)
            r_pts[ r_pts.first == pt ? 0 : -1 ] = new_pt

            replacement_edge = factory.create_line_string r_pts.map(&:coordinate).to_java(Coordinate)
            # logger.debug(self.class.name) { "Replacement edge is:" }
            # logger.debug(self.class.name) { replacement_edge.to_s }
            add_edge Pathfinder::LineString.new replacement_edge
            for_removal << edge
          end
        end

        for_removal.each { |edge| remove_edge edge }
      end

    #     for_removal = face.each_cons(2).map { |a,b| graph.edge(a,b) }
    #     for_removal.each { |edge| remove_edge edge }
    #   end


    end

    def indexes_for_multi_line_string mls
      index = LengthIndexedLine.new mls.jts_multi_line_string
      indexes = mls
        .map { |ls| [ls.first, ls.last] }
        .flatten
        .uniq
        .map { |pt| index.index_of pt.coordinate }
    end

    def visited? vertex
      @visited.include? vertex
    end

    def visit! vertex_or_array
      Array(vertex_or_array).each { |vertex| @visited << vertex }
    end



    # def reduce
    #   modified! false
    #   logger = Pathfinder.logger

    #   loop do
    #     face = find_a_face
    #     logger.debug(self.class.name) { "Found face: " }
    #     logger.debug(self.class.name) { face.to_s }
    #     return false unless face

    #     furthest_pair = face.furthest_vertex_pair
    #     logger.debug(self.class.name) { "Furthest vertex pair: #{furthest_pair.map { |pt| pt.to_s }.join(' ')}" }
    #     v1, v2 = furthest_pair

    #     pair = face.longest_edge_multi_line_strings

    #     logger.debug(self.class.name) { "Furthest linestring pair:" }
    #     logger.debug(self.class.name) { pair.first.to_s }
    #     logger.debug(self.class.name) { pair.last.to_s }

    #     if too_far_apart? pair
    #       logger.debug(self.class.name) { "Linstrings are too far apart.  Abandoning face reduction" }
    #       next
    #     end

    #     mls1, mls2 = pair
    #     ls1 = MultiLineString.ls_from_mls mls1
    #     ls2 = MultiLineString.ls_from_mls mls2
    #     averaged_line = LineString.average ls1, ls2
    #     logger.debug(self.class.name) { "Created initial averaged line" }
    #     logger.debug(self.class.name) { averaged_line.to_s }
    #     logger.debug(self.class.name) { "Averaged line based on these linestrings" }
    #     logger.debug(self.class.name) { ls1 }
    #     logger.debug(self.class.name) { ls2 }

    #     ls1 = MultiLineString.ls_from_mls mls1
    #     ls2 = MultiLineString.ls_from_mls mls2
    #     indexes = (indexes_for_multi_line_string(mls1) + indexes_for_multi_line_string(mls2)).sort
    #     averaged_mls = MultiLineString.break_line_string averaged_line, indexes

    #     averaged_mls.each { |ls| add_edge ls }
    #     logger.debug(self.class.name) { "Averaged line as mls" }
    #     logger.debug(self.class.name) { averaged_mls.to_s }

    #     factory = GeometryFactory.new PrecisionModel.new, 4326
    #     indexed_avg = LengthIndexedLine.new averaged_line.jts_line_string

    #     [mls1, mls2].each do |mls|
    #       logger.debug(self.class.name) { "Working with MLS item: " }
    #       logger.debug(self.class.name) { mls.to_s }
    #       first_points = mls.map { |line| line.first } - furthest_pair
    #       first_points.each do |pt|
    #         logger.debug(self.class.name) { "Working with pt: #{pt}" }
    #         index = mls.index pt
    #         logger.debug(self.class.name) { "Index for new point on mls is: #{index}" }
    #         new_pt = factory.create_point indexed_avg.extract_point index
    #         logger.debug(self.class.name) { "New Point: #{new_pt}" }
    #         face.off_face_edges(pt).each do |edge|
    #           logger.debug(self.class.name) { "Off Face Edge: " }
    #           logger.debug(self.class.name) { edge.to_s }
    #           r_pts = Array(edge)
    #           r_pts[ r_pts.first == pt ? 0 : -1 ] = new_pt

    #           replacement_edge = factory.create_line_string r_pts.map(&:coordinate).to_java(Coordinate)
    #           logger.debug(self.class.name) { "Replacement edge is:" }
    #           logger.debug(self.class.name) { replacement_edge.to_s }
    #           add_edge Pathfinder::LineString.new replacement_edge
    #           remove_edge edge
    #         end
    #       end
    #     end

    #     for_removal = face.each_cons(2).map { |a,b| graph.edge(a,b) }
    #     for_removal.each { |edge| remove_edge edge }
    #   end
    #   modified?
    # end

  end
end