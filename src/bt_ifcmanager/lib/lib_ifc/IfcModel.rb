#  IfcModel.rb
#
#  Copyright 2017 Jan Brouwer <jan@brewsky.nl>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#
#

require_relative 'IfcLabel.rb'
require_relative 'IfcIdentifier.rb'
require_relative 'ObjectCreator.rb'
require_relative 'step_writer.rb'

require_relative File.join('IFC2X3', 'IfcOwnerHistory.rb')
require_relative File.join('IFC2X3', 'IfcPersonAndOrganization.rb')
require_relative File.join('IFC2X3', 'IfcPerson.rb')
require_relative File.join('IFC2X3', 'IfcOrganization.rb')
require_relative File.join('IFC2X3', 'IfcApplication.rb')

require_relative File.join('IFC2X3', 'IfcProject.rb')
require_relative File.join('IFC2X3', 'IfcCartesianPoint.rb')
require_relative File.join('IFC2X3', 'IfcDirection.rb')

require_relative File.join('IFC2X3', 'IfcGeometricRepresentationContext.rb')

module BimTools
 module IfcManager
  require File.join(PLUGIN_PATH_LIB, 'layer_visibility.rb')

  class IfcModel
    include BimTools::IFC2X3
    
    # (?) possible additional methods:
    # - get_ifc_objects(hash ifc->su)
    # - get_su_objects(hash su->ifc)
    # - add_su_object
    # - add_ifc_object
    
    attr_accessor :owner_history, :representationcontext, :layers, :materials, :classifications, :classificationassociations
    attr_reader :su_model, :project, :ifc_objects, :export_summary, :options
    
    # creates an IFC model based on given su model
    # (?) could be enhanced to also accept other sketchup objects
    def initialize( su_model, options = {} )
      
      defaults = {
        ifc_entities:       false,                                  # include IFC entity types given in array, like ["IfcWindow", "IfcDoor"], false means all
        hidden:             false,                                  # include hidden sketchup objects
        attributes:         ['SU_DefinitionSet', 'SU_InstanceSet'], # include specific attribute dictionaries given in array as IfcPropertySets, like ['SU_DefinitionSet', 'SU_InstanceSet'], false means all
        classifications:    true,                                   # add all SketchUp classifications
        layers:             true,                                   # create IfcPresentationLayerAssignments
        materials:          true,                                   # create IfcMaterials
        styles:             true,                                   # create IfcStyledItems
        geometry:           true,                                   # create geometry for entities
        fast_guid:          false,                                  # create simplified guids
        dynamic_attributes: true,                                   # export dynamic component data
        mapped_items:       false
      }
      @options = defaults.merge( options )
      
      @su_model = su_model
      @ifc_id = 0
      @export_summary = Hash.new
      
      # create collections for materials and layers
      @materials = Hash.new
      @layers = Hash.new
      @classifications = Array.new
      
      # create empty array that will contain all IFC objects
      @ifc_objects = Array.new

      # create empty hash that will contaon all Mapped Representations (Component Definitions)
      @mapped_representations = Hash.new
      
      # create IfcOwnerHistory for all IFC objects
      @owner_history = create_ownerhistory()
      
      # create new IfcProject
      @project = create_project( su_model )
      
      # create IfcGeometricRepresentationContext for all IFC geometry objects
      @representationcontext = create_representationcontext()
        
      @project.representationcontexts = IfcManager::Ifc_Set.new([@representationcontext])
      
      # create IFC objects for all su instances
      create_ifc_objects( su_model )
    end
    
    # add object to ifc_objects array
    def add( ifc_object )
      @ifc_objects << ifc_object
      return new_id()
    end
    
    # add object to mapped representations Hash
    def add_mapped_representation( su_definition, ifc_object )
      @mapped_representations[ su_definition ] = ifc_object
    end
    
    # get mapped representation for component definition
    def mapped_representation?( su_definition )
      return @mapped_representations[ su_definition ]
    end
    
    def new_id()
      @ifc_id += 1
    end
    
    # write the IfcModel to given filepath
    # (?) could be enhanced to also accept multiple ifc types like step / ifczip / ifcxml
    # (?) could be enhanced with export options hash
    def export( file_path )
      IfcStepWriter.new( self, 'file_schema', 'file_description', file_path, @su_model )
    end
    
    # add object class name to export summary
    def summary_add( class_name )
      if @export_summary[class_name]
        @export_summary[class_name] += 1
      else
        @export_summary[class_name] = 1
      end
    end
    
    # create new IfcProject
    def create_project( su_model )
      project = IfcProject.new(self)
    end
    
    # Create new IfcOwnerHistory
    def create_ownerhistory()
      owner_history = IfcOwnerHistory.new( self )
      owner_history.owninguser = IfcPersonAndOrganization.new( self )
      owner_history.owninguser.theperson = IfcPerson.new( self )
      owner_history.owninguser.theperson.familyname = BimTools::IfcManager::IfcLabel.new( "" )
      owner_history.owninguser.theorganization = IfcOrganization.new( self )
      owner_history.owninguser.theorganization.name = BimTools::IfcManager::IfcLabel.new( "BIM-Tools" )
      owner_history.owningapplication = IfcApplication.new( self )
      owner_history.owningapplication.applicationdeveloper = owner_history.owninguser.theorganization
      owner_history.owningapplication.version = BimTools::IfcManager::IfcLabel.new( VERSION )
      owner_history.owningapplication.applicationfullname = BimTools::IfcManager::IfcLabel.new( "IFC manager for sketchup" )
      owner_history.owningapplication.applicationidentifier = BimTools::IfcManager::IfcIdentifier.new( "su_ifcmanager" )
      owner_history.changeaction = '.ADDED.'
      owner_history.creationdate = Time.now.to_i.to_s
      return owner_history
    end
    
    # Create new IfcGeometricRepresentationContext
    def create_representationcontext()
      representationcontext = IfcGeometricRepresentationContext.new( self )
      representationcontext.contexttype = BimTools::IfcManager::IfcLabel.new( "Model" )
      representationcontext.coordinatespacedimension = '3'
      representationcontext.worldcoordinatesystem = IfcAxis2Placement3D.new( self )
      representationcontext.worldcoordinatesystem.location = IfcCartesianPoint.new( self, Geom::Point3d.new(0,0,0) )
      representationcontext.truenorth = IfcDirection.new( self, Geom::Vector3d.new(0,1,0) )
      return representationcontext
    end
    
    # create IFC objects for all su instances
    def create_ifc_objects( sketchup_objects )
      if sketchup_objects.is_a? Sketchup::Model
        faces = Array.new
        entities = sketchup_objects.entities
        entitiy_count = entities.length
        i = 0
        while i < entitiy_count
          ent = entities[i]
        
          # skip hidden objects if skip-hidden option is set
          unless @options[:hidden] == false && (ent.hidden? || !BimTools::IfcManager::layer_visible?(ent.layer))
            case ent
            when Sketchup::Group, Sketchup::ComponentInstance
              transformation = Geom::Transformation.new
              ObjectCreator.new( self, ent, transformation, @project, {IfcProject=>@project} )
            when Sketchup::Face
              faces << ent
            end
          end
          i += 1
        end
        
        # create IfcBuildingelementProxy from all 'loose' faces combined
        unless faces.empty?
          ifc_entity = IfcBuildingElementProxy.new(self, nil)
          ifc_entity.name = BimTools::IfcManager::IfcLabel.new("Default Building Element")
          ifc_entity.representation = IfcProductDefinitionShape.new(self, nil)
          brep = IfcFacetedBrep.new( self, faces, Geom::Transformation.new )
          ifc_entity.representation.representations.first.items.add( brep )
          ifc_entity.objectplacement = IfcLocalPlacement.new(self, Geom::Transformation.new)
          
          # Create spatial hierarchy
          parent_ifc = self.project.get_default_related_object #      parent is default site
          parent_ifc = parent_ifc.get_default_related_object #      parent is default building
          parent_ifc = parent_ifc.get_default_related_object #    parent is default buildingstorey
          
          parent_ifc.add_contained_element( ifc_entity )
        end
      end
      return ifc_objects
    end
  end
 end
end
