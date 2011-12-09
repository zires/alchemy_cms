class Admin::ElementsController < AlchemyController
  
  before_filter :set_translation
  
  filter_access_to [:new, :create, :order, :index], :attribute_check => false
  
  cache_sweeper :content_sweeper, :only => [:update]
  
  def index
    @page = Page.find(params[:page_id], :include => {:elements => :contents})
    @cells = @page.cells
    if @cells.blank?
      @elements = @page.elements.not_trashed
    else
      @elements = @page.elements_grouped_by_cells
    end
    render :layout => false
  end
  
  def list
    @page_id = params[:page_id]
    if @page_id.blank? && !params[:page_urlname].blank?
      @page_id = Page.find_by_urlname(params[:page_urlname]).id
    end
    @elements = Element.find_all_by_page_id_and_public(@page_id, true)
  end
  
  def new
    @page = Page.find_by_id(params[:page_id])
    @element = @page.elements.build
    @elements = Element.all_for_page(@page)
    clipboard_elements = get_clipboard('elements')
    unless clipboard_elements.blank?
      @clipboard_items = Element.all_from_clipboard_for_page(clipboard_elements, @page)
    end
    render :layout => false
  end
  
  # Creates a element as discribed in config/alchemy/elements.yml on page via AJAX.
  def create
		@page = Page.find(params[:element][:page_id])
		@paste_from_clipboard = !params[:paste_from_clipboard].blank?
		if @paste_from_clipboard
			source_element = Element.find(element_from_clipboard[:id])
			@element = Element.copy(source_element, {:page_id => @page.id})
			if element_from_clipboard[:action] == 'cut'
				source_element.destroy
				@clipboard.delete_if { |i| i[:id].to_i == source_element.id }
			end
		else
			@element = Element.new_from_scratch(params[:element])
		end
    put_element_in_cell if @page.can_have_cells?
    @element.page = @page
    if @element.save
      render :action => :create
    else
      render_remote_errors(@element, 'form#new_element button.button')
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  # Saves all contents in the elements by calling save_content on each content
  # And then updates the element itself.
  # If a Ferret::FileNotFoundError raises we gonna catch it and rebuilding the index.
  def update
    @element = Element.find_by_id(params[:id])
    if @element.save_contents(params)
      @page = @element.page
      @element.public = !params[:public].nil?
      @element_validated = @element.save
    else
			@element_validated = false
			@notice = _('Validation failed.')
			@error_message = "<h2>#{@notice}</h2><p>#{_('Please check contents below.')}</p>".html_safe
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  # Trashes the Element instead of deleting it.
  def trash
    @element = Element.find(params[:id])
    @page_id = @element.page.id
    @element.trash
  rescue Exception => e
    exception_handler(e)
  end
  
  def order
    params[:element_ids].each do |element_id|
      element = Element.find(element_id)
      if element.trashed?
				element.page_id = params[:page_id]
				element.cell_id = params[:cell_id] if params[:cell_id]
				element.position = 1
      end
      element.move_to_bottom
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  def fold
    @element = Element.find(params[:id])
    @page = @element.page
    @element.folded = !@element.folded
		@element.save
  rescue Exception => e
    exception_handler(e)
  end

private

	def put_element_in_cell
		element_with_cell_name = @paste_from_clipboard ? params[:paste_from_clipboard] : params[:element][:name]
		cell_definition = Cell.definition_for(element_with_cell_name.split('#').last) if !element_with_cell_name.blank?
		if cell_definition
			@cell = @page.cells.find_or_create_by_name(cell_definition['name'])
			@element.cell = @cell
			return true
		else
			return false
		end
	end

	def element_from_clipboard
		@clipboard = get_clipboard(:elements)
		@clipboard.detect { |i| i[:id].to_i == params[:paste_from_clipboard].to_i }
	end

end